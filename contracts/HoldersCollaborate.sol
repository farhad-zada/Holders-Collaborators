// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ITokenClaims} from "./ITokenClaims.sol";

/*

PreREQUIREMENTS

___1___Two tokens
___2___Token claims for each token

*/
contract Collaborators is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    error Collaborate__BoostingNotComplete();
    error Collaborate__IntervalNotSet();
    error Collaborate__NotActive();
    error Collaborate__NotAdmin();
    error Collaborate__ContractLacksBalance(address token);
    error Collaborate__OverMax();
    error Collaborate__UnderMin();
    error Collaborate__BoostingComplete();
    error Collaborate__OverFull();
    error Collaborate__TimeOver();
    error Collaborate__NoClaimable();
    error Collaborate__InvalidToken();
    error Collaborate__LengthMismatch();
    error Collaborate__NoBoosting();

    uint8 private LEVEL;
    uint256 private base;
    // address[] private boosters;
    TokenData[] private tokens;
    Interval private interval;
    Imperatives private imperatives;
    Status private status;
    bool private reentrant = false;

    // address => admin status
    mapping(address => bool) private admins;
    // token => whitelist account => status
    mapping(address => mapping(address => bool)) private whitelist;
    // token => level => booster => amount
    mapping(address => mapping(uint8 => mapping(address => uint256 amount)))
        private boostings;
    // level => LevelDetails
    mapping(uint8 => LevelDetails) private levelDetails;
    // token => LEVEL => amount boosted
    mapping(address => mapping(uint8 => uint256)) private totalBoostToken;

    enum Status {
        WAITING,
        ACTIVE,
        PAUSED,
        COMPLETED
    }

    struct Interval {
        uint256 startsAt;
        uint256 endsAt;
        bool intervalSet;
    }
    struct TokenData {
        address token;
        string name;
        uint256 baseRelative;
        ITokenClaims claimsAddress;
    }
    struct Imperatives {
        uint256 commonMaxBoost;
        uint256 commonMinBoost;
        uint256 whitelistMaxBoost;
        uint256 whitelistMinBoost;
        bool imperativesSet;
    }
    struct LevelDetails {
        uint256 threshold;
        uint256 rewardPercent;
    }

    event StatusSet(Status status);
    event Admin(address admin, bool status);
    event Boost(address booster, address indexed token, uint256 amount);
    event Withdraw(address booster, address indexed token, uint256 amount);
    event ClaimsSet(address booster, address indexed token, uint256 amount);
    event Whitelist(address indexed token, address account, bool status);
    event LevelUpgrade(uint8 from, uint8 to, address token, uint256 amount);
    event Level(uint8 _level);

    // -> M

    modifier nonReentrant() {
        require(!reentrant, "Try again. Reentrancy");
        reentrant = true;
        _;
        reentrant = false;
    }

    modifier admin() {
        if (!admins[msg.sender]) revert Collaborate__NotAdmin();
        _;
    }

    modifier boostingAvailable(TokenData memory tokenData, uint256 amount) {
        if (status != Status.ACTIVE) revert Collaborate__NotActive();

        (uint256 maxOf, uint256 minOf) = _minMaxOf(tokenData, msg.sender);

        if (boostings[tokenData.token][LEVEL][msg.sender] + amount > maxOf)
            revert Collaborate__OverMax();

        if (boostings[tokenData.token][LEVEL][msg.sender] + amount < minOf)
            revert Collaborate__UnderMin();

        uint256 threshold = _thresholdOfToken(tokenData, LEVEL);

        if (totalBoostToken[tokenData.token][LEVEL] >= threshold)
            revert Collaborate__BoostingComplete();

        if (totalBoostToken[tokenData.token][LEVEL] + amount > threshold)
            revert Collaborate__OverFull();

        if (!interval.intervalSet) revert Collaborate__IntervalNotSet();

        if (interval.startsAt > block.timestamp)
            revert Collaborate__NotActive();

        if (interval.endsAt < block.timestamp) revert Collaborate__TimeOver();

        _;
    }

    modifier boostingComplete(uint8 _level) {
        for (uint i; i < tokens.length; i++) {
            uint256 threshold = _thresholdOfToken(tokens[i], _level);
            if (totalBoostToken[tokens[i].token][_level] < threshold)
                revert Collaborate__BoostingNotComplete();
        }
        _;
    }

    modifier upgradeAvailable(uint8 level) {
        require(LEVEL > level, "Coll: upgrade not available");
        require(levelDetails[level].threshold > 0, "Coll: incorrect level");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
        base = 10 ** 18;
        LEVEL = 1;
        admins[msg.sender] = true;
    }

    // -> W

    function addToken(
        address token,
        string calldata name,
        uint256 baseRelative,
        ITokenClaims claimsAddress
    ) public admin returns (bool) {
        for (uint i; i < tokens.length; i++) {
            if (tokens[i].token == token) {
                tokens[i] = TokenData(token, name, baseRelative, claimsAddress);
                return false;
            }
        }
        tokens.push(TokenData(token, name, baseRelative, claimsAddress));
        return true;
    }

    function setImperatives(
        uint256 commonMaxBoost,
        uint256 commonMinBoost,
        uint256 whitelistMaxBoost,
        uint256 whitelistMinBoost
    ) public admin {
        imperatives = Imperatives(
            commonMaxBoost,
            commonMinBoost,
            whitelistMaxBoost,
            whitelistMinBoost,
            true
        );
    }

    function setInterval(uint256 startsAt, uint256 endsAt) public onlyOwner {
        require(startsAt < endsAt, "Collaborate: Interval must be gt 0");
        interval = Interval(startsAt, endsAt, true);
    }

    function setWhitelist(
        address token,
        address[] memory accounts,
        bool[] memory statuses
    ) public admin {
        require(
            accounts.length == statuses.length,
            "Collaborate: mismatch of values"
        );
        for (uint i; i < accounts.length; i++) {
            whitelist[token][accounts[i]] = statuses[i];
            emit Whitelist(token, accounts[i], statuses[i]);
        }
    }

    function setStatus(uint8 _status) public admin {
        if (!interval.intervalSet) revert Collaborate__IntervalNotSet();
        require(tokens.length >= 2, "Collaborate: tokens not set");
        if (status != Status(_status)) {
            status = Status(_status);
        }
    }

    function setLevelsDetails(
        uint8[] calldata levels,
        uint256[] calldata thresholds,
        uint256[] calldata rewardPercents
    ) public admin {
        if (
            levels.length != thresholds.length ||
            levels.length != rewardPercents.length
        ) revert Collaborate__LengthMismatch();
        for (uint i; i < levels.length; i++) {
            levelDetails[levels[i]] = LevelDetails(
                thresholds[i],
                rewardPercents[i]
            );
        }
    }

    // -> B

    function boost(address token, uint256 amount) public {
        (, TokenData memory tokenData) = _tokenExists(token);
        bool success = _beforeBoostAndUpgrade(tokenData, amount);
        require(success, "Collaborators: smth went wrong!");
        _boost(token, amount);
    }

    function upgradeLevel(
        address token,
        uint8 level
    ) public upgradeAvailable(level) {
        (, TokenData memory tokenData) = _tokenExists(token);
        uint256 amount = boostings[token][level][msg.sender];
        if (amount == 0) revert Collaborate__NoBoosting();
        _beforeBoostAndUpgrade(tokenData, amount);
        delete boostings[token][level][msg.sender];
        emit LevelUpgrade(level, LEVEL, token, amount);
    }

    function withdrawBoostingAndSetClaims(
        address token,
        uint8 level
    ) public boostingComplete(level) nonReentrant {
        (, TokenData memory tokenData) = _tokenExists(token);

        IERC20Upgradeable _boostedToken = IERC20Upgradeable(token);

        (uint256 amount, uint256 baseReward) = _calcRewardInBase(
            tokenData,
            msg.sender,
            level
        );

        if (amount == 0) revert Collaborate__NoBoosting();
        uint256 rewardAmount;
        ITokenClaims[] memory _claims = new ITokenClaims[](tokens.length - 1);
        uint256[] memory _amounts = new uint256[](tokens.length - 1);

        uint index = 0;
        for (uint i; i < tokens.length; i++) {
            if (tokens[i].token == token) {
                continue;
            }

            rewardAmount = _calcRewardInToken(tokens[i], baseReward);
            IERC20Upgradeable _token = IERC20Upgradeable(tokens[i].token);
            if (rewardAmount > _token.balanceOf(address(this))) {
                revert Collaborate__ContractLacksBalance(tokens[i].token);
            }

            _amounts[index] = rewardAmount;
            _claims[index] = tokens[i].claimsAddress;
            index++;
        }

        address[] memory beneficiaries = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        beneficiaries[0] = msg.sender;

        for (uint i; i < _claims.length; i++) {
            amounts[0] = _amounts[i];
            _claims[i].setAllocations(beneficiaries, amounts, true);
            emit ClaimsSet(msg.sender, token, rewardAmount);
        }

        // PROTECT

        _boostedToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);

        delete boostings[token][level][msg.sender];
    }

    // -> I

    function _beforeBoostAndUpgrade(
        TokenData memory tokenData,
        uint256 amount
    ) internal boostingAvailable(tokenData, amount) returns (bool) {
        boostings[tokenData.token][LEVEL][msg.sender] =
            boostings[tokenData.token][LEVEL][msg.sender] +
            amount;
        totalBoostToken[tokenData.token][LEVEL] += amount;
        return true;
    }

    function _boost(address token, uint256 amount) internal {
        SafeERC20Upgradeable.safeTransferFrom(
            IERC20Upgradeable(token),
            msg.sender,
            address(this),
            amount
        );
    }

    function _tokenExists(
        address token
    ) internal view returns (bool exists, TokenData memory tokenData) {
        for (uint i; i < tokens.length; i++) {
            if (tokens[i].token == token) {
                return (true, tokens[i]);
            }
        }
        revert Collaborate__InvalidToken();
    }

    function _minMaxOf(
        TokenData memory _token,
        address account
    ) internal view returns (uint256 maxOf, uint256 minOf) {
        if (whitelist[_token.token][account]) {
            minOf =
                (imperatives.whitelistMinBoost * base) /
                _token.baseRelative;
            maxOf =
                (imperatives.whitelistMaxBoost * base) /
                _token.baseRelative;
        } else {
            minOf = (imperatives.commonMinBoost * base) / _token.baseRelative;
            maxOf = (imperatives.commonMaxBoost * base) / _token.baseRelative;
        }
    }

    function _thresholdOfToken(
        TokenData memory tokenData,
        uint8 _level
    ) internal view returns (uint256) {
        return (levelDetails[_level].threshold * base) / tokenData.baseRelative;
    }

    function _calcRewardInToken(
        TokenData memory tokenData,
        uint256 baseReward
    ) internal pure returns (uint256 reward) {
        reward = (baseReward * 10 ** 18) / tokenData.baseRelative;
    }

    function _calcRewardInBase(
        TokenData memory tokenData,
        address account,
        uint8 level
    ) internal view returns (uint256 amount, uint256 baseReward) {
        amount = boostings[tokenData.token][level][account];
        uint256 baseAmount = (amount * tokenData.baseRelative) / base;
        baseReward = (baseAmount * levelDetails[level].rewardPercent) / 100;
    }

    // -> R

    function getThreshold(uint8 level) public view returns (uint256) {
        return levelDetails[level].threshold;
    }

    function getTokenData(
        address token
    ) public view returns (TokenData memory tokenData) {
        (, tokenData) = _tokenExists(token);
    }

    function isAdmin(address account) public view returns (bool) {
        return admins[account];
    }

    function getTokens() public view returns (TokenData[] memory) {
        return tokens;
    }

    function getTokenTreshold(
        address token,
        uint8 level
    ) public view returns (uint256) {
        (, TokenData memory tokenData) = _tokenExists(token);
        uint256 threshold = _thresholdOfToken(tokenData, level);
        return threshold;
    }

    function getMyBoosting(
        address token,
        uint8 level
    ) public view returns (uint256) {
        return boostings[token][level][msg.sender];
    }

    function getBoostingComplete(
        uint8 level
    ) public view boostingComplete(level) returns (bool) {
        return true;
    }

    function getBase() public view returns (uint256) {
        return base;
    }

    function getCurrentLevel() public view returns (uint256) {
        return LEVEL;
    }

    function getInterval()
        public
        view
        returns (uint256 startsAt, uint256 endsAt)
    {
        return (interval.startsAt, interval.endsAt);
    }

    function getStatus() public view returns (Status) {
        return status;
    }

    function getImperatives()
        public
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            imperatives.commonMaxBoost,
            imperatives.commonMinBoost,
            imperatives.whitelistMaxBoost,
            imperatives.whitelistMinBoost
        );
    }

    function getLevelDetails(
        uint8 level
    ) public view returns (uint256, uint256) {
        return (
            levelDetails[level].threshold,
            levelDetails[level].rewardPercent
        );
    }

    function getTotalBoost(
        address token,
        uint8 level
    ) public view returns (uint256) {
        return totalBoostToken[token][level];
    }

    // -> U

    function updateToken(
        address token,
        string calldata name,
        uint256 baseRelative,
        ITokenClaims claimsAddress
    ) public admin returns (bool) {
        for (uint i; i < tokens.length; i++) {
            if (tokens[i].token == token) {
                tokens[i] = TokenData(token, name, baseRelative, claimsAddress);
                return true;
            }
        }
        return false;
    }

    function updateLevel(uint8 _level) public admin {
        LEVEL = _level;
        emit Level(_level);
    }

    // -> TMP

    function getMaxMin(
        address _token
    ) public view returns (uint256 maxOf, uint256 minOf) {
        (, TokenData memory tokenData) = _tokenExists(_token);
        return _minMaxOf(tokenData, msg.sender);
    }

    function getBoostingStarted() public view returns (bool) {
        return interval.intervalSet && interval.startsAt < block.timestamp;
    }

    function getBoostingEnded() public view returns (bool) {
        return interval.intervalSet && interval.endsAt < block.timestamp;
    }

    function timestamp(uint256 plus) public view returns (uint256) {
        return block.timestamp + plus;
    }
}
