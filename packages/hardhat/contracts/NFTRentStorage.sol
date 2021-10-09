pragma solidity >=0.6.0 <0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NFTRentStorage is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    enum NFTRentLineStatus {
        NOT_CREATED,
        REQUESTED,
        ACTIVE,
        CLOSED,
        CANCELLED,
        DEFAULTED
    }

    enum QuoteStatus {
        REQUESTED,
        ACCEPTED,
        REJECTED,
        FIXED
    }

    uint256 public NFTRentLineCounter;
    uint256 public constant yearInSeconds = 365 days;
    uint256 public feeFraction = 10;
    uint256 public stakeFraction = 50;
    uint256 public liquidation = 20;
    uint256 public expertFee = feeFraction.mul(10**28);
    uint256 public expertStake = stakeFraction.mul(10**28);
    uint256 public liquidationThreshold = liquidation.mul(10**30);

    struct QuoteVars {
        address NFTRent;
        uint256 NFTId;
        address NFTOwner;
        uint256 maxRentalDuration;
        uint256 dailyRentalPrice;
        uint256 repayInterval;
        address collateralAsset;
        uint256 collateralAmount;
        address expert;
        bool verified;
        QuoteStatus quoteStatus;
        bool Toescrow;
        bool Towallet;
    }

    struct NFTRentLineUsageVars {
        uint256 repayments;
        uint256 withdrawInterval;
        uint256 repaymentInterval;
        uint256 repaymentsCompleted;
        uint256 _rentalPrice;
        uint256 loanStartTime;
        uint256 lastRepaymentTime;
    }

    struct NFTRentLineVars {
        bool exists;
        address lender;
        address borrower;
        uint256 rentalPrice;
        address NftAsset;
        uint256 NftId;
        address collateralAsset;
        NFTRentLineStatus currentStatus;
    }
    mapping(bytes32 => NFTRentLineUsageVars) public NFTRentLineUsage;
    mapping(bytes32 => NFTRentLineVars) public NFTRentLineInfo;
    mapping(address => mapping(uint256 => QuoteVars)) public quoteVarsInfo;
}