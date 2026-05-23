// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIPReceiver} from "./vendor/CCIPReceiver.sol";
import {Client} from "./vendor/Client.sol";
import {IRouterClient} from "./vendor/IRouterClient.sol";

/// @title CrossChainInvestment
/// @notice Accepts real-estate investment arriving from another chain via **Chainlink CCIP**. The
///         same contract is deployed on each chain: on the source chain it sends tokens + data
///         (`sendInvestment`); on the destination chain it receives them (`_ccipReceive`) and
///         credits the beneficiary's pending allocation for a given property.
/// @dev Demonstrates the key CCIP safety control — allowlisting trusted source chains *and*
///      sender addresses — plus carrying both tokens and structured data in one message.
///      See docs/ccip.md.
contract CrossChainInvestment is CCIPReceiver, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Fee token for CCIP (e.g. LINK). The contract must hold a balance to pay fees.
    IERC20 public immutable feeToken;
    /// @notice Gas limit for the receiver callback on the destination chain.
    uint256 public destGasLimit = 200_000;

    // Allowlists (the single most important CCIP control).
    mapping(uint64 => bool) public allowlistedDestinationChains; // for sending
    mapping(uint64 => bool) public allowlistedSourceChains; // for receiving
    mapping(address => bool) public allowlistedSenders; // for receiving

    /// @notice Credited cross-chain investment, per property and beneficiary (in arriving token units).
    mapping(bytes32 => mapping(address => uint256)) public pendingInvestment;

    event InvestmentSent(
        bytes32 indexed messageId,
        uint64 indexed destChainSelector,
        bytes32 indexed propertyId,
        address beneficiary,
        address token,
        uint256 amount,
        uint256 fee
    );
    event InvestmentReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        bytes32 indexed propertyId,
        address beneficiary,
        address token,
        uint256 amount
    );
    event DestinationChainAllowlisted(uint64 selector, bool allowed);
    event SourceChainAllowlisted(uint64 selector, bool allowed);
    event SenderAllowlisted(address sender, bool allowed);

    error DestinationChainNotAllowlisted(uint64 selector);
    error SourceChainNotAllowlisted(uint64 selector);
    error SenderNotAllowlisted(address sender);
    error NothingReceived();
    error InsufficientFeeBalance(uint256 needed, uint256 have);

    constructor(address router, address feeToken_) CCIPReceiver(router) Ownable(msg.sender) {
        require(feeToken_ != address(0), "feeToken=0");
        feeToken = IERC20(feeToken_);
    }

    // --- allowlist admin -----------------------------------------------------

    function allowlistDestinationChain(uint64 selector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[selector] = allowed;
        emit DestinationChainAllowlisted(selector, allowed);
    }

    function allowlistSourceChain(uint64 selector, bool allowed) external onlyOwner {
        allowlistedSourceChains[selector] = allowed;
        emit SourceChainAllowlisted(selector, allowed);
    }

    function allowlistSender(address sender, bool allowed) external onlyOwner {
        allowlistedSenders[sender] = allowed;
        emit SenderAllowlisted(sender, allowed);
    }

    function setDestGasLimit(uint256 gasLimit) external onlyOwner {
        destGasLimit = gasLimit;
    }

    // --- send (source chain) -------------------------------------------------

    /// @notice Send an investment of `amount` of `investToken` to fund `propertyId` for `beneficiary`
    ///         on the destination chain. Pulls the invest tokens from the caller; pays the CCIP fee
    ///         from this contract's feeToken balance.
    function sendInvestment(
        uint64 destChainSelector,
        address receiver,
        address investToken,
        uint256 amount,
        bytes32 propertyId,
        address beneficiary
    ) external returns (bytes32 messageId) {
        if (!allowlistedDestinationChains[destChainSelector]) {
            revert DestinationChainNotAllowlisted(destChainSelector);
        }

        IERC20(investToken).safeTransferFrom(msg.sender, address(this), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: investToken, amount: amount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(propertyId, beneficiary),
            tokenAmounts: tokenAmounts,
            feeToken: address(feeToken),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: destGasLimit, allowOutOfOrderExecution: true})
            )
        });

        IRouterClient router = IRouterClient(getRouter());
        uint256 fee = router.getFee(destChainSelector, message);
        uint256 feeBal = feeToken.balanceOf(address(this));
        if (feeBal < fee) revert InsufficientFeeBalance(fee, feeBal);

        feeToken.forceApprove(address(router), fee);
        IERC20(investToken).forceApprove(address(router), amount);

        messageId = router.ccipSend(destChainSelector, message);
        emit InvestmentSent(messageId, destChainSelector, propertyId, beneficiary, investToken, amount, fee);
    }

    // --- receive (destination chain) -----------------------------------------

    /// @inheritdoc CCIPReceiver
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (!allowlistedSourceChains[message.sourceChainSelector]) {
            revert SourceChainNotAllowlisted(message.sourceChainSelector);
        }
        address sender = abi.decode(message.sender, (address));
        if (!allowlistedSenders[sender]) revert SenderNotAllowlisted(sender);
        if (message.destTokenAmounts.length == 0) revert NothingReceived();

        (bytes32 propertyId, address beneficiary) = abi.decode(message.data, (bytes32, address));

        Client.EVMTokenAmount memory received = message.destTokenAmounts[0];
        pendingInvestment[propertyId][beneficiary] += received.amount;

        emit InvestmentReceived(
            message.messageId,
            message.sourceChainSelector,
            propertyId,
            beneficiary,
            received.token,
            received.amount
        );
    }

    // --- treasury ------------------------------------------------------------

    /// @notice Fund the contract with fee tokens (LINK) used to pay for outbound CCIP messages.
    function depositFeeToken(uint256 amount) external {
        feeToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Owner can sweep any ERC-20 held by the contract (e.g. received invest tokens).
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}
