// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MTN} from "src/MTN.sol";
import {WMTN} from "src/WMTN.sol";
import {StakingMTN} from "src/StakingMTN.sol";
import {VaultAutocompound} from "src/VaultAutocompound.sol";
import {Deposit, IStakingMTN} from "src/Deposit.sol";

contract SystemTest is Test {
    MTN mtn;
    WMTN wmtn;
    StakingMTN staking;
    VaultAutocompound vault;
    Deposit dep;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        mtn = new MTN();
        wmtn = new WMTN();
        staking = new StakingMTN(ERC20(address(mtn)));
        vault = new VaultAutocompound(ERC20(address(wmtn)));
        dep = new Deposit(ERC20(address(mtn)), wmtn, IStakingMTN(address(staking)), vault);

        // Wire roles and permissions
        vault.setDepositContract(address(dep));
        // Grant roles from DEFAULT_ADMIN_ROLE holder (deployer of WMTN in setUp is this contract)
        wmtn.grantRole(wmtn.MINTER_ROLE(), address(dep));
        wmtn.grantRole(wmtn.BURNER_ROLE(), address(dep));

        // Fund users
        mtn.mint(alice, 1_000e18);
        mtn.mint(bob, 1_000e18);

        // No default approvals; tests set exact amounts per call
    }

    function test_DepositNonCompound_MintsWmtnAndStakes() public {
        // Approve exact amount
        vm.startPrank(alice);
        mtn.approve(address(dep), 100e18);
        dep.deposit(alice, false);
        vm.stopPrank();

        assertEq(wmtn.balanceOf(alice), 100e18, "wMTN minted to user");
        // Staking should hold 100 deposited from deposit contract
        assertEq(staking.balanceOf(address(dep)), 100e18, "staked by deposit");
        assertEq(dep.totalMTNDeposited(), 100e18);
        assertEq(dep.totalWMTNMinted(), 100e18);
    }

    function test_DepositCompound_MintsShares() public {
        vm.startPrank(bob);
        mtn.approve(address(dep), 200e18);
        dep.deposit(bob, true);
        vm.stopPrank();

        // Shares minted 1:1 initially
        uint256 shares = vault.balanceOf(bob);
        assertEq(shares, 200e18, "aMTN minted");
        assertEq(vault.totalAssets(), 200e18, "vault staked assets track deposit");
    }

    function test_Redeem_BurnsWmtn_WithdrawsMTN() public {
        // First deposit non-compound to get wMTN
        vm.startPrank(alice);
        mtn.approve(address(dep), 120e18);
        dep.deposit(alice, false);
        vm.stopPrank();

        // Redeem 50 MTN
        vm.startPrank(alice);
        dep.redeem(50e18, alice);
        vm.stopPrank();

        assertEq(wmtn.balanceOf(alice), 70e18, "wMTN burned");
        assertEq(mtn.balanceOf(alice), 1_000e18 - 120e18 + 50e18, "MTN returned");
    }

    function test_RewardFlow_HarvestStreamsToVault() public {
        // Seed: Bob compounds into vault so there are vault shares
        vm.startPrank(bob);
        mtn.approve(address(dep), 300e18);
        dep.deposit(bob, true);
        vm.stopPrank();
        assertEq(vault.totalAssets(), 300e18);

        // Fund staking contract with reward tokens and notify
        // Move tokens to staking so it holds enough to cover rewards
        mtn.mint(address(this), 1_000e18);
        mtn.transfer(address(staking), 600e18);
        vm.warp(block.timestamp + 1);
        staking.notifyRewardAmount(600e18);

        // Advance time to accrue rewards for deposit (as a staker)
        vm.warp(block.timestamp + 3 days);
        // Harvest at deposit: claims rewards and restakes; mints wMTN to vault and notifies
        dep.harvest();

        // Vault should now have an active reward stream
        uint256 rate = vault.rewardRate();
        assertGt(rate, 0, "vault rewardRate set");

        // Let some streaming happen
        vm.warp(block.timestamp + 2 days);
        uint256 beforeAssets = vault.totalAssets();
        // Harvest in vault to stake accrued rewards into backing
        uint256 harvested = vault.harvest();
        assertGt(harvested, 0, "harvested > 0");
        assertEq(vault.totalAssets(), beforeAssets + harvested, "assets increased by harvest");

        // Share value should have increased for bob
        uint256 shares = vault.balanceOf(bob);
        uint256 assetsNow = vault.convertToAssets(shares);
        assertGt(assetsNow, 300e18, "share value increased");
    }
}
