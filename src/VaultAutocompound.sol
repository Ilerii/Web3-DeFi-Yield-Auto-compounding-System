// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/tokens/ERC4626.sol";

// ERC4626 autocompounding vault for wMTN with streamed rewards
contract VaultAutocompound is ERC4626 {
    // Reward streaming state
    uint256 public rewardRate; // tokens per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;
    uint256 public constant REWARDS_DURATION = 7 days;

    // Accounting of "staked" assets backing shares
    uint256 public totalStaked;

    // Access: only deposit contract can notify; owner configures deposit
    address public depositContract;
    address public owner;

    event Harvest(uint256 amount);
    event RewardAdded(uint256 reward);

    modifier onlyDeposit() { require(msg.sender == depositContract, "ONLY_DEPOSIT"); _; }
    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }

    constructor(ERC20 _asset) ERC4626(_asset, "Auto-Compound MTN", "aMTN") {
        owner = msg.sender;
        lastUpdateTime = block.timestamp;
    }

    function setDepositContract(address _deposit) external onlyOwner {
        depositContract = _deposit;
    }

    // Hooks: track staked supply on deposit/mint and withdraw/redeem
    function afterDeposit(uint256 assets, uint256) internal override {
        _stake(assets);
    }

    function beforeWithdraw(uint256 assets, uint256) internal override {
        _withdrawInternal(assets);
    }

    // Internal accounting helpers
    function _stake(uint256 amount) internal {
        totalStaked += amount;
    }

    function _withdrawInternal(uint256 amount) internal {
        totalStaked -= amount;
    }

    // ERC4626 view
    function totalAssets() public view override returns (uint256) {
        // Only count staked assets; rewards increase as harvested
        return totalStaked;
    }

    // Reward helpers
    function lastTimeRewardApplicable() public view returns (uint256) {
        if (periodFinish == 0) return block.timestamp; // no active period
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    // Total rewards accrued and not yet harvested; equals elapsed * rate
    function earned() public view returns (uint256) {
        if (rewardRate == 0) return 0;
        uint256 applicable = lastTimeRewardApplicable();
        if (applicable <= lastUpdateTime) return 0;
        return (applicable - lastUpdateTime) * rewardRate;
    }

    // Harvest streamed rewards into staked backing
    function harvest() external returns (uint256 amt) {
        // Update global accumulator
        rewardPerTokenStored = rewardPerToken();
        uint256 applicable = lastTimeRewardApplicable();
        amt = (applicable - lastUpdateTime) * rewardRate;
        lastUpdateTime = applicable;
        if (amt > 0) {
            totalStaked += amt; // stake the accrued rewards
            emit Harvest(amt);
        }
    }

    // Start a new reward streaming period. Only deposit contract may call.
    function notifyRewardAmount() external onlyDeposit {
        // Calculate current pending rewards BEFORE mutating timestamps
        uint256 pending = earned();
        // Update accumulator with current state
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        // Determine newly deposited tokens meant for rewards:
        // current balance minus already-staked and already-earned
        uint256 bal = asset.balanceOf(address(this));
        uint256 newly = bal - totalStaked - pending;
        require(newly > 0, "NO_NEW_REWARDS");

        // Set reward parameters
        if (block.timestamp >= periodFinish) {
            rewardRate = newly / REWARDS_DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (newly + leftover) / REWARDS_DURATION;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;
        emit RewardAdded(newly);
    }
}
