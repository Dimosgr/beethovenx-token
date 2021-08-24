// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@boringcrypto/boring-solidity/contracts/libraries/BoringMath.sol";
import "@boringcrypto/boring-solidity/contracts/BoringBatchable.sol";
import "@boringcrypto/boring-solidity/contracts/BoringOwnable.sol";
import "./BeethovenToken.sol";
import "./libraries/SignedSafeMath.sol";
import "./interfaces/IRewarder.sol";

interface IMigratorChef {
    // Perform LP token migration from legacy UniswapV2 to BeethovenSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // BeethovenSwap must mint EXACTLY the same amount of BeethovenSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Beethoven. He can make Beethoven and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is BoringOwnable {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringERC20 for IERC20;
    using SignedSafeMath for int256;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBeethovenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBeethovenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
//        IERC20 lpToken; // Address of LP token contract.
        // we have a fixed number of SUSHI tokens released per block, each pool gets his fraction based on the allocPoint
        uint256 allocPoint; // How many allocation points assigned to this pool. the fraction  SUSHIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs.
        uint256 accBeethovenPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
    }
    // The SUSHI TOKEN!
    BeethovenToken public beethoven;
    // Dev address.
    address public devaddr;

    // Treasury address.
    address public treasuryaddr;

    // BEETHOVEn tokens created per block.
    uint256 public beethovenPerBlock;

    uint256 private constant ACC_BEETHOVEN_PRECISION = 1e12;

    // Percentage of pool rewards that goto the devs.
    uint256 public devPercent;
    // Percentage of pool rewards that goes to the treasury.
    uint256 public treasuryPercent;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens per pool. poolId => address => userInfo
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;

    /// @notice Address of each `IRewarder` contract in MCV2.
    IRewarder[] public rewarder;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SUSHI mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accSushiPerShare);
    event SetDevAddress(address indexed oldAddress, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 _joePerSec);

    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        BeethovenToken _beethoven,
        address _devaddr,
        address _treasuryaddr,
        uint256 _beethovenPerBlock,
        uint256 _startBlock,
        uint256 _devPercent,
        uint256 _treasuryPercent
    ) public {
        require(
            0 <= _devPercent && _devPercent <= 1000,
            "constructor: invalid dev percent value"
        );
        require(
            0 <= _treasuryPercent && _treasuryPercent <= 1000,
            "constructor: invalid treasury percent value"
        );
        require(
            _devPercent + _treasuryPercent <= 1000,
            "constructor: total percent over max"
        );
        beethoven = _beethoven;
        devaddr = _devaddr;
        treasuryaddr = _treasuryaddr;
        beethovenPerBlock = _beethovenPerBlock;
        startBlock = _startBlock;
        devPercent = _devPercent;
        treasuryPercent = _treasuryPercent;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) public onlyOwner {
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accBeethovenPerShare: 0
            })
        );
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken, _rewarder);
    }

    // Update the given pool's BEETHOVEN allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite
    ) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        if (overwrite) { rewarder[_pid] = _rewarder; }
        poolInfo[_pid].allocPoint = _allocPoint.to64();
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "MasterChef: no migrator set");
        IERC20 _lpToken = lpToken[_pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "MasterChef: migrated balance must match");
        lpToken[_pid] = newLpToken;
    }

    // View function to see pending BEETHOVENs on frontend.
    function pendingBeethoven(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // how many beethovens per lp token
        uint256 accBeethovenPerShare = pool.accBeethovenPerShare;
        // total staked lp tokens in this pool
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            // just use blocks ?
//            uint256 multiplier =
//                getMultiplier(pool.lastRewardBlock, block.number);
//
//            uint256 beethovenReward =
//                multiplier.mul(beethovenPerBlock).mul(pool.allocPoint).div(
//                    totalAllocPoint
//                );
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 beethovenReward= multiplier
            .mul(beethovenPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint)
            .mul(1000 - devPercent - treasuryPercent)
            .div(1000);
            accBeethovenPerShare = accBeethovenPerShare.add(
                beethovenReward.mul(ACC_BEETHOVEN_PRECISION).div(lpSupply)
            );
        }
        pending = user.amount.mul(accBeethovenPerShare).div(ACC_BEETHOVEN_PRECISION).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool){
        pool = poolInfo[pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (block.number > pool.lastRewardBlock) {
            // total lp tokens
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
//                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                uint256 multiplier = block.number.sub(pool.lastRewardBlock);
                // rewards for this pool based on his allocation points
//                uint256 beethovenReward =
//                    multiplier.mul(beethovenPerBlock).mul(pool.allocPoint).div(
//                        totalAllocPoint
//                    );

                uint256 beethovenReward = multiplier.mul(beethovenPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
                uint256 lpPercent = 1000 - devPercent - treasuryPercent;
                beethoven.mint(devaddr, beethovenReward.mul(devPercent).div(1000));
                beethoven.mint(treasuryaddr, beethovenReward.mul(treasuryPercent).div(1000));
                beethoven.mint(address(this), beethovenReward.mul(lpPercent).div(1000));
                pool.accBeethovenPerShare = pool.accJoePerShare.add(
                    beethovenReward.mul(ACC_BEETHOVEN_PRECISION).div(lpSupply).mul(lpPercent).div(1000)
                );
            }
            pool.lastRewardBlock = block.number;
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.accSushiPerShare);
        }
    }

    // Deposit LP tokens to MasterChef for BEETHOVEN allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][to];

        // Effects
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.rewardDebt.add(int256(_amount.mul(pool.accSushiPerShare) / ACC_BEETHOVEN_PRECISION));

        // Interactions
        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onBeethovenReward(_pid, to, to, 0, user.amount);
        }

        lpToken[_pid].safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount, to);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {

        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(int256(_amount.mul(pool.accSushiPerShare) / ACC_BEETHOVEN_PRECISION));
        user.amount = user.amount.sub(_amount);

        // Interactions
        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onBeethovenReward(_pid, msg.sender, to, 0, user.amount);
        }

        lpToken[_pid].safeTransfer(to, _amount);

        emit Withdraw(msg.sender, _pid, _amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SUSHI rewards.
    function harvest(uint256 _pid, address _to) public {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        int256 accumulatedBeethoven = int256(user.amount.mul(pool.accBeethovenPerShare) / ACC_BEETHOVEN_PRECISION);
        uint256 _pendingBeethoven = accumulatedBeethoven.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedBeethoven;

        // Interactions
        if (_pendingBeethoven != 0) {
            safeBeethovenTransfer(_to, _pendingBeethoven);
        }

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onBeethovenReward( _pid, msg.sender, _to, _pendingBeethoven, user.amount);
        }

        emit Harvest(msg.sender, _pid, _pendingBeethoven);
    }


    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SUSHI rewards.
    function withdrawAndHarvest(uint256 _pid, uint256 _amount, address _to) public {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        int256 accumulatedBeethoven = int256(user.amount.mul(pool.accBeethovenPerShare) / ACC_BEETHOVEN_PRECISION);
        uint256 _pendingBeethoven = accumulatedBeethoven.sub(user.rewardDebt).toUInt256();

        user.rewardDebt = accumulatedBeethoven.sub(int256(_amount.mul(pool.accBeethovenPerShare) / ACC_BEETHOVEN_PRECISION));
        user.amount = user.amount.sub(_amount);

        safeBeethovenTransfer(_to, _pendingBeethoven);

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onBeethovenReward(_pid, msg.sender, _to, _pendingBeethoven, user.amount);
        }

        lpToken[_pid].safeTransfer(_to, _amount);

        emit Withdraw(msg.sender, _pid, _amount, _to);
        emit Harvest(msg.sender, _pid, _pendingBeethoven);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = rewarder[_pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onBeethovenReward(_pid, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[_pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount, to);
    }

    // Safe beethoven transfer function, just in case if rounding error causes pool to not have enough BEETHOVENs.
    function safeBeethovenTransfer(address _to, uint256 _amount) internal {
        uint256 beethovenBal = beethoven.balanceOf(address(this));
        if (_amount > beethovenBal) {
            beethoven.transfer(_to, beethovenBal);
        } else {
            beethoven.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setDevPercent(uint256 _newDevPercent) public onlyOwner {
        require(
            0 <= _newDevPercent && _newDevPercent <= 1000,
            "setDevPercent: invalid percent value"
        );
        require(
            treasuryPercent + _newDevPercent <= 1000,
            "setDevPercent: total percent over max"
        );
        devPercent = _newDevPercent;
    }

    function setTreasuryPercent(uint256 _newTreasuryPercent) public onlyOwner {
        require(
            0 <= _newTreasuryPercent && _newTreasuryPercent <= 1000,
            "setTreasuryPercent: invalid percent value"
        );
        require(
            devPercent + _newTreasuryPercent <= 1000,
            "setTreasuryPercent: total percent over max"
        );
        treasuryPercent = _newTreasuryPercent;
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission,
    // here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _joePerSec) public onlyOwner {
        massUpdatePools();
        joePerSec = _joePerSec;
        emit UpdateEmissionRate(msg.sender, _joePerSec);
    }
}