// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MeSa Token (MESA)
/// @notice ERC20 with mint/burn, fee (treasury+burn), pause, blacklist, RBAC
contract MeSaToken is ERC20, ERC20Burnable, Pausable, AccessControl {
    // --- Roles ---
    bytes32 public constant MINTER_ROLE       = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE       = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE  = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant BLACKLISTER_ROLE  = keccak256("BLACKLISTER_ROLE");

    // --- Fees (in basis points; 10000 = 100%) ---
    // totalFeeBps = treasuryFeeBps + burnFeeBps  (must be <= MAX_TOTAL_FEE_BPS)
    uint16 public constant MAX_TOTAL_FEE_BPS = 1000; // max 10% total fee (change if needed)
    uint16 public treasuryFeeBps; // part of fee that goes to treasury
    uint16 public burnFeeBps;     // part of fee that is burned

    address public treasury;      // where fee (treasury part) is sent
    mapping(address => bool) public feeExempt;     // addresses exempt from fee
    mapping(address => bool) public blacklisted;   // addresses blocked from transfer

    event FeesUpdated(uint16 treasuryFeeBps, uint16 burnFeeBps, address indexed treasury);
    event FeeExemptSet(address indexed account, bool isExempt);
    event BlacklistSet(address indexed account, bool isBlacklisted);

    constructor(
        uint256 initialSupply,
        address admin,
        address treasury_,
        uint16 treasuryFeeBps_,
        uint16 burnFeeBps_
    ) ERC20("MeSa", "MESA") {
        // Set roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(BLACKLISTER_ROLE, admin);

        // Set treasury & fees
        _setFees(treasury_, treasuryFeeBps_, burnFeeBps_);

        // Exempt admin and treasury from fees by default
        feeExempt[admin] = true;
        feeExempt[treasury_] = true;

        // Initial mint to admin
        _mint(admin, initialSupply);
    }

    // --- Admin: Pause/Unpause ---
    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // --- Admin: Fees ---
    function setFees(address treasury_, uint16 treasuryFeeBps_, uint16 burnFeeBps_)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        _setFees(treasury_, treasuryFeeBps_, burnFeeBps_);
    }

    function _setFees(address treasury_, uint16 treasuryFeeBps_, uint16 burnFeeBps_) internal {
        require(treasury_ != address(0), "Treasury=0");
        require(uint256(treasuryFeeBps_) + uint256(burnFeeBps_) <= MAX_TOTAL_FEE_BPS, "Fee too high");

        treasury = treasury_;
        treasuryFeeBps = treasuryFeeBps_;
        burnFeeBps = burnFeeBps_;

        emit FeesUpdated(treasuryFeeBps, burnFeeBps, treasury);
    }

    function setFeeExempt(address account, bool isExempt) external onlyRole(FEE_MANAGER_ROLE) {
        feeExempt[account] = isExempt;
        emit FeeExemptSet(account, isExempt);
    }

    // --- Blacklist (freeze) ---
    function setBlacklisted(address account, bool isBlacklisted_)
        external
        onlyRole(BLACKLISTER_ROLE)
    {
        blacklisted[account] = isBlacklisted_;
        emit BlacklistSet(account, isBlacklisted_);
    }

    // --- Mint (RBAC-controlled) ---
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // --- Core transfer hook with fee, pause, blacklist checks ---
    // OZ v4.9+/_5.x uses _update as the central state-change hook for transfers/mint/burn.
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        // disallow transfers from/to blacklisted accounts (except mint/burn paths)
        if (from != address(0)) require(!blacklisted[from], "Sender blacklisted");
        if (to   != address(0)) require(!blacklisted[to],   "Recipient blacklisted");

        // Apply fee only on "real" transfers (not mint or burn)
        bool takeFee = (from != address(0) && to != address(0)) && !(feeExempt[from] || feeExempt[to]);

        if (!takeFee || (treasuryFeeBps == 0 && burnFeeBps == 0)) {
            // No fee path
            super._update(from, to, value);
        } else {
            uint256 totalFeeBps = uint256(treasuryFeeBps) + uint256(burnFeeBps);
            // value * totalFeeBps / 10000
            uint256 fee = (value * totalFeeBps) / 10_000;
            uint256 toBurn = (value * burnFeeBps) / 10_000;
            uint256 toTreasury = fee - toBurn;
            uint256 net = value - fee;

            // Move net to recipient
            super._update(from, to, net);

            // Send treasury part
            if (toTreasury > 0) {
                super._update(from, treasury, toTreasury);
            }

            // Burn part
            if (toBurn > 0) {
                // Burning reduces totalSupply; route tokens to address(0)
                super._update(from, address(0), toBurn);
            }
        }
    }
}
