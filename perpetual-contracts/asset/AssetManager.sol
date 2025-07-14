// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "./IAssetManager.sol";
import "./AssetDao.sol";

contract AssetManager is IAssetManager {
    address public gov;
    bool public isPaused;
    mapping(AssetDao.AssetCategory => bool) public isCategoryPaused;
    mapping(AssetDao.AssetCategory => AssetDao.TradingHours) public tradingHoursByCategory;
    mapping(AssetDao.AssetCategory => mapping(uint256 => bool)) public isCloseDate;

    event UpdateGov(address gov);
    event TradingPaused(bool isPaused);
    event CategoryTradingPaused(AssetDao.AssetCategory category, bool isPaused);
    event CategoryTradingHoursUpdated(AssetDao.AssetCategory category, AssetDao.TradingHours tradingHours);
    event CloseDayUpdated(AssetDao.AssetCategory category, uint256 date, bool isClose);

    modifier onlyGov() {
        require(msg.sender == gov, "Not gov");
        _;
    }

    constructor() {
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        if (_gov != address(0)) {
            gov = _gov;
            emit UpdateGov(_gov);
        }
    }

    function pauseTrading(bool _pause) external onlyGov {
        isPaused = _pause;
        emit TradingPaused(_pause);
    }

    function pauseCategoryTrading(AssetDao.AssetCategory _category, bool _pause) external onlyGov {
        isCategoryPaused[_category] = _pause;
        emit CategoryTradingPaused(_category, _pause);
    }

    function setCategoryTradingHours(AssetDao.AssetCategory _category, AssetDao.TradingHours memory _tradeHours) external onlyGov {
        tradingHoursByCategory[_category] = _tradeHours;
        emit CategoryTradingHoursUpdated(_category, _tradeHours);
    }

    function setCloseDay(AssetDao.AssetCategory _category, uint256 _date, bool _isClose) external onlyGov {
        isCloseDate[_category][_date] = _isClose;
        emit CloseDayUpdated(_category, _date, _isClose);
    }

    function getTradingHoursByCategory(uint256 _category) external view returns (
        uint8 startHourUTC,
        uint8 startMinuteUTC,
        uint8 endHourUTC,
        uint8 endMinuteUTC,
        uint8 startDayOfWeek,
        uint8 endDayOfWeek,
        uint8 breakStartHourUTC,
        uint8 breakStartMinuteUTC,
        uint8 breakEndHourUTC,
        uint8 breakEndMinuteUTC
    ) {
        AssetDao.TradingHours memory info = tradingHoursByCategory[AssetDao.AssetCategory(_category)];
        return (info.startHourUTC, info.startMinuteUTC, info.endHourUTC, info.endMinuteUTC, info.startDayOfWeek, info.endDayOfWeek,
                info.breakStartHourUTC, info.breakStartMinuteUTC, info.breakEndHourUTC, info.breakEndMinuteUTC);
    }

    function isTradingOpen(uint256 _category) external view returns (bool) {
        require(_category <= uint256(AssetDao.AssetCategory.JP_STOCK), "Invalid category");
        return _isTradingOpen(AssetDao.AssetCategory(_category), block.timestamp);
    }

    function isTradingOpenAt(uint256 _category, uint256 _timestamp) external view returns (bool) {
        require(_category <= uint256(AssetDao.AssetCategory.JP_STOCK), "Invalid category");
        return _isTradingOpen(AssetDao.AssetCategory(_category), _timestamp);
    }

    function _isTradingOpen(AssetDao.AssetCategory _category, uint256 _timestamp) internal view returns (bool) {
        if (isPaused) return false;
        if (isCategoryPaused[_category]) return false;
        if (_category == AssetDao.AssetCategory.NONE || _category == AssetDao.AssetCategory.TOKEN) return true;

        (uint16 minuteOfDay, uint8 weekday, uint256 today) = _getUTCMinuteOfDayWeekdayDate(_timestamp);
        if (isCloseDate[_category][today]) return false;

        AssetDao.TradingHours memory workHours = tradingHoursByCategory[_category];
        uint16 start = uint16(workHours.startHourUTC) * 60 + workHours.startMinuteUTC;
        uint16 end = uint16(workHours.endHourUTC) * 60 + workHours.endMinuteUTC;
        if (weekday < workHours.startDayOfWeek || weekday > workHours.endDayOfWeek) return false;
        if (minuteOfDay < start || minuteOfDay >= end) return false;

        uint256 breakStart = uint16(workHours.breakStartHourUTC) * 60 + workHours.breakStartMinuteUTC;
        uint256 breakEnd = uint16(workHours.breakEndHourUTC) * 60 + workHours.breakEndMinuteUTC;
        if (minuteOfDay >= breakStart && minuteOfDay < breakEnd) return false;

        return true;
    }

    function _getUTCMinuteOfDayWeekdayDate(uint256 _timestamp) internal pure returns (uint16 minuteOfDay, uint8 weekday, uint256 yyyymmdd) {
        uint256 secondsInDay = _timestamp % 86400;
        minuteOfDay = uint16(secondsInDay / 60);

        weekday = uint8((_timestamp / 86400 + 4) % 7);
        if (weekday == 0) weekday = 7;

        uint256 daysSinceEpoch = _timestamp / 86400;
        uint256 z = daysSinceEpoch + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 day = doy - (153 * mp + 2) / 5 + 1;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        year += (month <= 2 ? 1 : 0);

        yyyymmdd = year * 10000 + month * 100 + day;
    }
}