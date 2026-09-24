// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openZeppelin/contracts/token/ERC20/ERC20.sol";
import "@openZeppelin/contracts/access/Ownable.sol";

/**
 * @title MemeBattleToken
 * @dev ERC20 token with Anti-Whale, 30s Cooldown, and Cross-Team Tax Routing.
 */
 contract MemeBattleToken is ERC20, Ownable {
    address public battleEngine;
    address public founderWallet;
    address public opposingToken;
    address public pancakePair;

    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;
    uint256 public constant COOLDOWN_TIME = 30 seconds;
    uint256 public constant PERMANENT_SELL_TAX = 100;
    uint256 public constant PAPERHANDS_SELL_TAX = 1000;
    uint256 public constant PROTECTION_PERIOD = 24 hours;

    uint256 public penaltySellTax = 0;

    mapping(address => uint256) public lastTransactionTimestamp;
    mapping(address => uint256) public lastPurchaseTimestamp;

    mapping(address => bool) public isTaxExempt;
    mapping(address => uint256) public taxExemptUntil;

    modifier onlyBattleEngine() {
        require(msg.sender == battleEngine, "MemeBattleToken: Only BattleEngine allowed");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _battleEngine,
        address _founderWallet
    ) ERC20(name, symbol) Ownable(msg.sender) {
        require(_battleEngine != address(0), "MemeBattleToken: Zero address check failed");
        require(_founderWallet != address(0), "MemeBattleToken: Zero address check failed");

        battleEngine = _battleEngine;
        founderWallet = _founderWallet;

        uint256 total = initialSupply * 10**decimals();
        _mint(msg.sender, total); // 100% of tokens generated allocated to deployer wallet

        // Anti-Whale strict sizing: 0.5% transaction ceiling, 1% max wallet capacity
        maxTxAmount = total / 200;
        maxWalletAmount = total / 100;

        isTaxExempt[msg.sender] = true;
        isTaxExempt[_battleEngine] = true;
        isTaxExempt[_founderWallet] = true;
    }

    /**
     * @dev One-time initialization matrix to link market liquidity components.
     * Must be finalized before ownership renunciation.
     */
     function initializeMarket(address _opposingToken, address _pancakePair) external onlyOwner {
        require(opposingToken == address(0), "MemeBattleToken: Liquidity connections already hardlocked");
        require(_opposingToken != address(0) && _pancakePair != address(0), "MemeBattleToken: Invalid market pairing target");

        opposingToken = _opposingToken;
        pancakePair = _pancakePair;

        isTaxExempt[_pancakePair] = true;
     }

     // --- Game Engine interface Hooks ---
     function gameMint(address to, uint256 amount) external onlyBattleEngine {
        _mint(to, amount);
     }

     function gameBurn(address from, uint256 amount) external onlyBattleEngine {
        _burn(from, amount);
     }

     function setPenaltyTax(uint256 _penaltyTax) external onlyBattleEngine {
        require(_penaltyTax <= 5000, "MemeBattleToken: Game-driven penalties cannot exceed 50%");
        penaltySellTax = _penaltyTax;
     }

     function setUserTaxExemption(address user, uint256 untilTimestamp) external onlyBattleEngine {
        taxExemptUntil[user] = untilTimestamp;
     }

     // --- Token Transfer Overrides & Protection Middleware ---
     function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {

            // 1. Anti-Bot Cooldown Enforcement Loop
            if (!isTaxExempt[from]) {
                require(block.timestamp >= lastTransactionTimestamp[from] + COOLDOWN_TIME, "MemeBattleToken: Bot mitigation active. Wait 30s.");
                lastTransactionTimestamp[from] = block.timestamp;
            }
            if (!isTaxExempt[to]) {
                lastTransactionTimestamp[to] = block.timestamp;
            }

            // 2. Anti-Whale Dynamic Evaluation
            if (!isTaxExempt[from] && !isTaxExempt[to]) {
                require(value <= maxTxAmount, "MemeBattleToken: Transaction exceeds single execution limit.");
                require(balanceOf(to) + value <= maxWalletAmount, "MemeBattleToken: Target wallet allocation threshold reached.");
            }

            // MARKET BUY DETECTION: Track block execution time for incoming transfers from PancakeSwap Pool
            if (from == pancakePair && !isTaxExempt[to]) {
                lastPurchaseTimestamp[to] = block.timestamp;
            }

            // MARKET SELL DETECTION: Evaluate tax metrics if interacting with PancakeSwap Pool
            if (to == pancakePair && !isTaxExempt[from] && block.timestamp > taxExemptUntil[from]) {
                uint256 dynamicSellTax = PERMANENT_SELL_TAX;
                uint256 opposingTeamTaxAmount = 0;

                // Paperhands Check: Trigger 10% penalty fee if selling inside the 24-hour window
                if (block.timestamp < lastPurchaseTimestamp[from] + PROTECTION_PERIOD) {
                    dynamicSellTax += PAPERHANDS_SELL_TAX;
                }

                // Add active game penalty variables if applied by the win-streak mechanisms
                if (penaltySellTax > 0) {
                    dynamicSellTax += penaltySellTax;
                }

                uint256 totalTaxAmount = (value * dynamicSellTax) / 10000;

                if (totalTaxAmount > 0) {
                    uint256 founderTaxAmount = (value * PERMANENT_SELL_TAX) / 10000;

                    if (block.timestamp < lastPurchaseTimestamp[from] + PROTECTION_PERIOD) {
                        opposingTeamTaxAmount = (value * PAPERHANDS_SELL_TAX) / 10000;
                    }

                    uint256 gameEngineTaxAmount = totalTaxAmount - founderTaxAmount - opposingTeamTaxAmount;

                    // Routing Stream 1: 1% distributed to founder ledger
                    super._update(from, founderWallet, founderTaxAmount);

                    // Routing Stream 2: 10% penalty shipped directly into opposing team contract ledger
                    if (opposingTeamTaxAmount > 0 && opposingToken != address(0)) {
                        super._update(from, opposingToken, opposingTeamTaxAmount);
                    }

                    // Routing Stream 3: Round mechanics tax sent to BattleEngine address for future pools
                    if (gameEngineTaxAmount > 0) {
                        super._update(from, battleEngine, gameEngineTaxAmount);
                    }

                    super._update(from, to, value - totalTaxAmount);
                    return;
                }
            }
        }
        super._update(from, to, value);
     }
 }
