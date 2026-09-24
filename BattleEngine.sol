// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMemeToken is IERC20 {
    function gameMint(address to, uint256 amount) external;
    function gameBurn(address from, uint256 amount) external;
    function setPenaltyTax(uint256 _penaltyTax) external;
    function setUserTaxExemption(address user, uint256 untilTimestamp) external;
    function totalSupply() external view returns (uint256);
}

/**
 * @title BattleEngine - Part 1
 */
 contract BattleEngine is Ownable, ReentrancyGuard {
    address public dodgeLight;
    address public pepeDark;
    bool public tokensLinked = false;

    uint256 public lastCycleTimestamp;
    uint256 public constant CYCLE_DURATION = 24 hours;

    uint256 public votingStartTimestamp;
    uint256 public constant VOTING_DURATION = 4 hours;
    bool public isVotingActive = false;

    uint256 public constant TOKENS_PER_VOTE = 1000000 * 10**18;
    uint256 public constant FIFTY_BILLION = 50000000000 * 10**18;
    uint256 public constant ONE_HUNDRED_BILLION = 100000000000 * 10**18;
    uint256 public constant TWO_HUNDRED_BILLION = 200000000000 * 10**18;

    uint256 public currentRoundOptions;
    uint256 public currentRoundAttackTier;
    address public currentWinnerToken;

    mapping(uint256 => uint256) public tokenVotesForOption;

    uint256 public lightStreak;
    uint256 public darkStreak;
    uint256 public lightMintImmunityUntil;
    uint256 public darkMintImmunityUntil;
    uint256 public remainingWeakenedAttacksLight;
    uint256 public remainingWeakenedAttacksDark;
    uint256 private nonce;

    event NewRoundSettled(address indexed winner, uint256 attackTier, uint256 optionsProposed);
    event VoteCast(address indexed voter, address indexed tokenUsed, uint256 indexed optionIndex, uint256 amountOfTokens);
    event PenaltyExecuted(address indexed attacker, address indexed defender, uint256 attackTier, uint256 finalOptionExecuted, uint256 totalTokensSpentInVoting);
    event BattleGodAppeared(address indexed blessedTeam, uint256 blessingType);

    constructor() Ownable(msg.sender) {
        lastCycleTimestamp = block.timestamp;
    }

    function linkTokens(address _dodgeLight, address _pepeDark) external onlyOwner {
        require(!tokensLinked, "BattleEngine: Token configurations already locked");
        require(_dodgeLight != address(0) && _pepeDark != address(0), "BattleEngine: Invalid linking targets");
        dodgeLight = _dodgeLight;
        pepeDark = _pepeDark;
        tokensLinked = true;
    }

    function settleDailyCycle(uint256 lightVolume, uint256 darkVolume) external onlyOwner nonReentrant {
        require(tokensLinked, "BattleEngine: Faction tokens must be linked before initialization");
        require(block.timestamp >= lastCycleTimestamp + CYCLE_DURATION, "BattleEngine: Cycle interval constraint active");
        require(!isVotingActive, "BattleEngine: A verification session is already in active status");

        currentWinnerToken = (lightVolume >= darkVolume) ? dodgeLight : pepeDark;
        if (currentWinnerToken == dodgeLight) { lightStreak++; darkStreak = 0; }
        else { darkStreak++; lightStreak =0; }

        uint256 currentStreak = (currentWinnerToken == dodgeLight) ? lightStreak : darkStreak;
        if (currentStreak >= 5) {
            currentRoundAttackTier = 3;
        } else if (currentStreak >= 3) {
            currentRoundAttackTier = 2;
        } else {
            currentRoundAttackTier = 1;
        }

        generateThreeRandomOptions();

        tokenVotesForOption[0] = 0;
        tokenVotesForOption[1] = 0;
        tokenVotesForOption[2] = 0;

        votingStartTimestamp = block.timestamp;
        isVotingActive = true;

        emit NewRoundSettled(currentWinnerToken, currentRoundAttackTier, currentRoundOptions);

        if (getRandomNumber(100) < 10) triggerBattleGod();

        IMemeToken(dodgeLight).setPenaltyTax(0);
        IMemeToken(pepeDark).setPenaltyTax(0);

        lastCycleTimestamp = block.timestamp;
    }

    function castTokenVote(uint256 optionIndex, uint256 voteCount) external nonReentrant {
        require(isVotingActive, "BattleEngine: Voting operations are currently locked");
        require(block.timestamp < votingStartTimestamp + VOTING_DURATION, "BattleEngine: Voting period closed");
        require(optionIndex < 3, "BattleEngine: Invalid option selection boundary");
        require(voteCount > 0, "BattleEngine: Minimum vote threshold not met");

        uint256 totalTokenCost = voteCount * TOKENS_PER_VOTE;

        IMemeToken(currentWinnerToken).transferFrom(msg.sender, address(this), totalTokenCost);

        tokenVotesForOption[optionIndex] += totalTokenCost;

        emit VoteCast(msg.sender, currentWinnerToken, optionIndex, totalTokenCost);
    }

    function executeVotedPenalty() external nonReentrant {
        require(isVotingActive, "BattleEngine: No active voting session");
        require(block.timestamp >= votingStartTimestamp + VOTING_DURATION, "BattleEngine: 4-hour countdown active");

        uint256 winningIndex = 0;
        uint256 maxTokenAccumulated = tokenVotesForOption[0];

        if (tokenVotesForOption[1] > maxTokenAccumulated) {
            winningIndex = 1;
            maxTokenAccumulated = tokenVotesForOption[1];
        }
        if (tokenVotesForOption[2] > maxTokenAccumulated) {
            winningIndex = 2;
            maxTokenAccumulated = tokenVotesForOption[2];
        }

        uint256 winningOption;
        if (winningIndex == 0) {
            winningOption = currentRoundOptions % 10;
        } else if (winningIndex == 1) {
            winningOption = (currentRoundOptions / 10) % 10;
        } else {
            winningOption = (currentRoundOptions / 100) % 10;
        }

        address loserTeam = (currentWinnerToken == dodgeLight) ? pepeDark : dodgeLight;

        bool isWeakened = (currentWinnerToken == dodgeLight) ? (remainingWeakenedAttacksLight > 0) : (remainingWeakenedAttacksDark > 0);

        if (currentWinnerToken == dodgeLight && remainingWeakenedAttacksLight > 0) {
            remainingWeakenedAttacksLight--;
        }
        if (currentWinnerToken == pepeDark && remainingWeakenedAttacksDark > 0) {
            remainingWeakenedAttacksDark--;
        }

        if (currentRoundAttackTier == 1 || currentRoundAttackTier == 2) {
            executeBasicOrStrongAttack(currentWinnerToken, loserTeam, currentRoundAttackTier, winningOption, isWeakened);
        } else if (currentRoundAttackTier == 3) {
            executeUltimateAttack(currentWinnerToken, loserTeam, winningOption);
        }

        uint256 totalTokensCollected = tokenVotesForOption[0] + tokenVotesForOption[1] + tokenVotesForOption[2];
        isVotingActive = false;
        emit PenaltyExecuted(currentWinnerToken, loserTeam, currentRoundAttackTier, winningOption, totalTokensCollected);
    }

    function executeBasicOrStrongAttack(address winner, address loser, uint256 tier, uint256 option, bool isWeakened) internal {
        uint256 modifierMultiplier = (tier == 2) ? 140 : 100;
        if (isWeakened) modifierMultiplier = modifierMultiplier / 2;

        if (option == 1) {
            if ((loser == dodgeLight && block.timestamp < lightMintImmunityUntil) || (loser == pepeDark && block.timestamp < darkMintImmunityUntil)) return;
            IMemeToken(loser).gameMint(loser, (FIFTY_BILLION * modifierMultiplier) / 100);
        } else if (option == 2) {
            IMemeToken(loser).setPenaltyTax((3000 * modifierMultiplier) / 100);
        } else if (option == 3) {
            IMemeToken(loser).setPenaltyTax((4500 * modifierMultiplier) / 100);
        } else if (option == 4) {
            uint256 burnAmount = (IMemeToken(winner).balanceOf(winner) * 10) / 100;
            if (burnAmount > 0) IMemeToken(winner).gameBurn(winner, burnAmount);
        } else if (option == 5) {
            if (winner == dodgeLight) lightMintImmunityUntil = block.timestamp + 72 hours;
            else darkMintImmunityUntil = block.timestamp + 72 hours;
        }
    }

    function executeUltimateAttack(address winner, address loser, uint256 option) internal {
        if (option == 1) {
            if ((loser == dodgeLight && block.timestamp >= lightMintImmunityUntil) || (loser == pepeDark && block.timestamp >= darkMintImmunityUntil)) {
                IMemeToken(loser).gameMint(loser, TWO_HUNDRED_BILLION);
            }
            IMemeToken(winner).gameBurn(winner, ONE_HUNDRED_BILLION);
        } else if (option == 2) {
            if (loser == dodgeLight) remainingWeakenedAttacksLight = 5; else remainingWeakenedAttacksDark = 5;
        } else if (option == 3) {
            IMemeToken(loser).setPenaltyTax(5000);
        } else if (option == 4) {
            IMemeToken(winner).gameBurn(winner, FIFTY_BILLION);
        } else if (option == 5) {
            IMemeToken(winner).setUserTaxExemption(winner, block.timestamp + 24 hours);
        }
    }

    function triggerBattleGod() internal {
        address blessedTeam = (getRandomNumber(2) == 0) ? dodgeLight : pepeDark;
        uint256 blessingType = getRandomNumber(3);

        if (blessingType == 0) {
            if (blessedTeam == dodgeLight) lightMintImmunityUntil = block.timestamp + 5 days; else darkMintImmunityUntil = block.timestamp + 5 days;
        } else if (blessingType == 1) {
            IMemeToken(dodgeLight).gameBurn(dodgeLight, IMemeToken(dodgeLight).totalSupply() / 10);
            IMemeToken(pepeDark).gameBurn(pepeDark, IMemeToken(pepeDark).totalSupply() / 10);
        } else if (blessingType == 2) {
            IMemeToken(blessedTeam).setPenaltyTax(0);
        }
        emit BattleGodAppeared(blessedTeam, blessingType);
    }

    function generateThreeRandomOptions() internal {
        uint256 opt1 = (getRandomNumber(5)) + 1;
        uint256 opt2 = (getRandomNumber(5)) + 1;
        while (opt2 == opt1) {
            opt2 = (getRandomNumber(5)) + 1;
        }
        uint256 opt3 = (getRandomNumber(5)) + 1;
        while (opt3 == opt1 || opt3 == opt2) {
            opt3 = (getRandomNumber(5)) + 1;
        }

        currentRoundOptions = opt1 + (opt2 * 10) + (opt3 * 100);
    }

    function forwardLiquidity(address tokenAddress, address poolAddress, uint256 amount) external {
        require(msg.sender == owner() || msg.sender == founderWallet(), "Unauthorized: Access denied");
        IERC20(tokenAddress).transfer(poolAddress, amount);
    }

    function founderWallet() public view returns (address) {
        return IMemeToken(dodgeLight).balanceOf(address(0)) == 0 ? Ownable(dodgeLight).owner() : address(0);
    }

    function getRandomNumber(uint256 upperLimit) internal returns (uint256) {
        nonce++;
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, nonce))) % upperLimit;
    }
 }
