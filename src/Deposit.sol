// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {VaultAutocompound} from "src/VaultAutocompound.sol";
import {WMTN} from "src/WMTN.sol";

interface IStakingMTN {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
}

contract Deposit {
    ERC20 public immutable mtn;
    WMTN public immutable wmtn;
    IStakingMTN public immutable staking;
    VaultAutocompound public immutable vault;

    uint256 public totalMTNDeposited;
    uint256 public totalWMTNMinted;

    event Deposited(address indexed user, address indexed receiver, uint256 amount, bool compounded);
    event Redeemed(address indexed user, address indexed receiver, uint256 amount);
    event Harvested(uint256 rewardClaimed);
    event RewardSynced(uint256 newlyAdded);

    constructor(ERC20 _mtn, WMTN _wmtn, IStakingMTN _staking, VaultAutocompound _vault) {
        mtn = _mtn;
        wmtn = _wmtn;
        staking = _staking;
        vault = _vault;
        // Note: grant MINTER/BURNER on wMTN to this contract off-chain or via owner
    }

    // User deposits MTN; tokens get staked into staking contract.
    // If compound=false, mint wMTN 1:1 to receiver.
    // If compound=true, route wMTN into vault and receiver gets aMTN shares.
    // Matches assignment signature: deposit(address _receiver, bool _compound)
    // The amount taken is the current allowance approved to this contract.
    function deposit(address receiver, bool compound) external {
        uint256 amount = mtn.allowance(msg.sender, address(this));
        require(amount > 0, "NO_ALLOWANCE");
        // Pull MTN from user for 'amount'
        mtn.transferFrom(msg.sender, address(this), amount);
        // Stake into staking contract
        mtn.approve(address(staking), amount);
        staking.stake(amount);

        totalMTNDeposited += amount;

        if (!compound) {
            wmtn.mint(receiver, amount);
            totalWMTNMinted += amount;
        } else {
            // Mint to this contract then deposit into the vault on behalf of receiver
            wmtn.mint(address(this), amount);
            totalWMTNMinted += amount;
            wmtn.approve(address(vault), amount);
            vault.deposit(amount, receiver);
        }

        emit Deposited(msg.sender, receiver, amount, compound);
    }

    // Harvest MTN rewards from staking, re-stake them, and stream wMTN rewards to the vault.
    function harvest() external {
        uint256 beforeBal = mtn.balanceOf(address(this));
        staking.getReward();
        uint256 afterBal = mtn.balanceOf(address(this));
        uint256 claimed = afterBal - beforeBal;
        if (claimed > 0) {
            // Re-stake MTN rewards
            mtn.approve(address(staking), claimed);
            staking.stake(claimed);

            // Mint wMTN to the vault and notify new reward amount
            wmtn.mint(address(vault), claimed);
            vault.notifyRewardAmount();
            emit RewardSynced(claimed);
        }
        emit Harvested(claimed);
    }

    // Redeem MTN by burning wMTN and withdrawing from staking.
    function redeem(uint256 assets, address receiver) external {
        require(assets > 0, "ZERO");
        // burn caller's wMTN
        wmtn.burn(msg.sender, assets);

        // withdraw MTN from staking back to this contract then transfer to receiver
        staking.withdraw(assets);
        mtn.transfer(receiver, assets);
        emit Redeemed(msg.sender, receiver, assets);
    }
}
