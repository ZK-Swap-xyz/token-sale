// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/utils/Context.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

//grail sale contract with emergency withdraw https://arbiscan.io/address/0x66ec1ee6c3ad04d7629ce4a6d5d19ba99c365d29#code

contract PrivateSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error NotAllowedToMint();

    IERC20 public immutable salesToken;
    uint256 public immutable tokensToSell;
    uint256 public immutable ethersToRaise;
    uint256 public immutable refundThreshold;

    uint256 public startTime;
    uint256 public endTime;
    address public immutable burnAddress;

    uint256 public immutable minCommit;
    uint256 public immutable maxCommit;

    bool public started;
    bool public finished;

    uint256 public totalCommitments;
    mapping(address => uint256) public commitments;
    mapping(address => bool) public userClaimed;

    bytes32 private immutable merkleRootAllowList;

    event Commit(address indexed buyer, uint256 amount);
    event Claim(address indexed buyer, uint256 eth, uint256 token);
    event Claim2(address indexed buyer, uint256 token);

    constructor(
        IERC20 _salesToken,
        uint256 _tokensToSell, // 19,650,000
        uint256 _ethersToRaise, // 450 ether
        uint256 _refundThreshold, // 80 ether
        uint256 _minCommit, // 0.1 ether
        uint256 _maxCommit, // 2 ether
        address _burnAddress,
        bytes32 _root // set to treasury
    ) {
        require(_ethersToRaise > 0, "Ethers to raise should be greater than 0");
        require(
            _ethersToRaise > _refundThreshold,
            "Ethers to raise should be greater than refund threshold"
        );
        require(_minCommit > 0, "Minimum commitment should be greater than 0");
        require(
            _maxCommit >= _minCommit,
            "Maximum commitment should be greater or equal to minimum commitment"
        );

        salesToken = _salesToken;
        tokensToSell = _tokensToSell;
        ethersToRaise = _ethersToRaise;
        refundThreshold = _refundThreshold;
        minCommit = _minCommit;
        maxCommit = _maxCommit;
        burnAddress = _burnAddress;
        merkleRootAllowList = _root;
    }

    function setTime(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(
            _startTime >= block.timestamp,
            "Start time must be in the future."
        );
        require(
            _endTime > _startTime,
            "End time must be greater than start time."
        );
        startTime = _startTime;
        endTime = _endTime;
    }

    function start() external onlyOwner {
        require(!started, "Already started.");
        started = true;

        salesToken.safeTransferFrom(msg.sender, address(this), tokensToSell);
    }

    function commit(
        bytes32[] calldata _merkleProof
    ) external payable nonReentrant {
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        if (
            !MerkleProof.verifyCalldata(_merkleProof, merkleRootAllowList, leaf)
        ) revert NotAllowedToMint();
        require(
            started &&
            block.timestamp >= startTime &&
            block.timestamp < endTime,
            "Can only deposit Ether during the sale period."
        );

        require(
            minCommit <= commitments[msg.sender] + msg.value &&
            commitments[msg.sender] + msg.value <= maxCommit,
            "Commitment amount is outside the allowed range."
        );
        commitments[msg.sender] += msg.value;
        totalCommitments += msg.value;
        emit Commit(msg.sender, msg.value);
    }

    function simulateClaim(
        address account
    ) external view returns (uint256, uint256) {
        if (commitments[account] == 0) return (0, 0);

        if (totalCommitments >= refundThreshold) {
            uint256 ethersToSpend = Math.min(
                commitments[account],
                (commitments[account] * ethersToRaise) / totalCommitments
            );
            uint256 ethersToRefund = commitments[account] - ethersToSpend;
            uint256 tokensToReceive = (tokensToSell * ethersToSpend) /
            ethersToRaise;

            return (ethersToRefund, tokensToReceive);
        } else {
            uint256 amt = commitments[msg.sender];
            return (amt, 0);
        }
    }

    function claim() external nonReentrant returns (uint256, uint256) {
        require(
            block.timestamp > endTime,
            "Can only claim tokens after the sale has ended."
        );
        require(
            commitments[msg.sender] > 0,
            "You have not deposited any Ether."
        );

        require(userClaimed[msg.sender] != true, "has claimed");

        if (totalCommitments >= refundThreshold) {
            uint256 ethersToSpend = Math.min(
                commitments[msg.sender],
                (commitments[msg.sender] * ethersToRaise) / totalCommitments //// @audit-info multiplication before division - no issue
            );
            uint256 ethersToRefund = commitments[msg.sender] - ethersToSpend;
            uint256 tokensToReceive = (tokensToSell * ethersToSpend) /
            ethersToRaise;

            if (block.timestamp > endTime + 1 days) {
                // @audit-info token claimable 1 day after sale ended, refund claimable right away
                userClaimed[msg.sender] = true;

                salesToken.safeTransfer(msg.sender, tokensToReceive);

                emit Claim2(msg.sender, tokensToReceive);

                if (ethersToRefund > 0) {
                    (bool success, ) = msg.sender.call{value: ethersToRefund}(
                        ""
                    );
                    require(success, "Failed to transfer ether");
                }
            } else {
                if (ethersToRefund > 0) {
                    (bool success, ) = msg.sender.call{value: ethersToRefund}(
                        ""
                    );
                    require(success, "Failed to transfer ether");
                }
            }

            emit Claim(msg.sender, ethersToRefund, tokensToReceive);
            return (ethersToRefund, tokensToReceive);
        } else {
            uint256 amt = commitments[msg.sender];
            commitments[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: amt}("");
            require(success, "Failed to transfer ether");
            emit Claim(msg.sender, amt, 0);
            return (amt, 0);
        }
    }

    function finish() external onlyOwner {
        require(
            block.timestamp > endTime,
            "Can only finish after the sale has ended."
        );
        require(!finished, "Already finished.");
        finished = true;

        if (totalCommitments >= refundThreshold) {
            (bool success, ) = payable(owner()).call{
            value: Math.min(ethersToRaise, totalCommitments)
            }("");
            require(success, "Failed to transfer ether");
            if (ethersToRaise > totalCommitments) {
                uint256 tokensToBurn = (tokensToSell *
                (ethersToRaise - totalCommitments)) / ethersToRaise;
                salesToken.safeTransfer(burnAddress, tokensToBurn);
            }
        } else {
            salesToken.safeTransfer(owner(), tokensToSell);
        }
    }

    receive() external payable {}
}
