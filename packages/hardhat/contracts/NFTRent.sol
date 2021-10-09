pragma solidity >=0.6.0 <0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IVerification.sol";
import "./NFTRentStorage.sol";
// import './expertOnboard.sol';

contract NFTRent is Initializable, OwnableUpgradeable, NFTRentStorage {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    IVerification public verification;

    mapping(address => string) public expertData;
    mapping(address => mapping(uint256 => bool)) public quotes;
    mapping(address => mapping(uint256 => bytes32)) public NFTtoHash;
    mapping(address => bool) public VerifiedBorrowers;

    modifier OnlyExpert(address _expert) {
        require(bytes(expertData[_expert]).length != 0, 'The Expert alone can access this function');
        _;
    }

    modifier ifNFTRentLineExists(bytes32 NFTRentLineHash) {
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus != NFTRentLineStatus.NOT_CREATED, 'NFTRent Line does not exist');
        _;
    }

    modifier onlyNFTRentLineBorrower(bytes32 NFTRentLineHash) {
        require(NFTRentLineInfo[NFTRentLineHash].borrower == msg.sender, 'Only NFTRent line Borrower can access');
        _;
    }

    modifier onlyNFTRentLineLender(bytes32 NFTRentLineHash) {
        require(NFTRentLineInfo[NFTRentLineHash].lender == msg.sender, 'Only NFTRent line Lender can access');
        _;
    }

    // Add events here to get the updates on the requested quotes made by the lender
    event QuoteRequested(string _name, address _rentNft,uint256 _nftId, address _collateralAsset, uint256 _rentDuration);
    event QuoteReleased(string _name, address _rentNft,uint256 _nftId, address _collateralAsset, uint256 _rentDuration, uint256 _dailyRentalPrice, uint256 _collateralAmount);
    event QuoteAccepted(address NFTRent, uint256 DailyRentPrice);
    event QuoteRejected(address NFTRent, uint256 DailyRentPrice);
    event RentRequested(address NFTRent, bytes32 NFTRentHash, NFTRentLineStatus currentStatus);
    event RentActive(address NFTRent, bytes32 NFTRentHash, NFTRentLineStatus currentStatus);
    event RentClosed(address NFTRent, bytes32 NFTRentHash, NFTRentLineStatus currentStatus);
    event RentCancelled(address NFTRent, bytes32 NFTRentHash,  NFTRentLineStatus currentStatus);
    event RentDefaulted(address NFTRent, bytes32 NFTRentHash,  NFTRentLineStatus currentStatus);
    event Repaid(address _rentNft, uint256 repaymentsLeft);
    event LendingStopped(address _rentNft, uint256 _nftId);
    event QuoteProvided(address _rentNft, uint256 _NftId, uint256 _dailyRentPrice, uint256 _repayInterval, uint256 _collateralAmount);
    event BorrowerVerified(address _borrower);
    event VerifierAdded(address verifier, string metadata);
    event VerifierRemoved(address verifier);

    function initialize(address _admin, address _verification) public initializer {
        super.__Ownable_init();
        super.transferOwnership(_admin);
        verification = IVerification(_verification);
    }

    function addExpert(address _verifier, string calldata _metadata) external onlyOwner {
        require(bytes(expertData[_verifier]).length == 0, 'AddExpert: Verifier already exists');
        // verification.addVerifier(_verifier);
        verification.registerMasterAddress(_verifier, true);
        expertData[_verifier] = _metadata;
        emit VerifierAdded(_verifier, _metadata);
    }

    function removeExpert(address _verifier) external onlyOwner {
        require(bytes(expertData[_verifier]).length != 0, 'AddExpert: Verifier does not exists');
        delete expertData[_verifier];
        verification.unregisterMasterAddress(_verifier, address(this));
        // verification.removeVerifier(_verifier);
        emit VerifierRemoved(_verifier);
    }

    function requestQuote(
        address _rentNft,
        uint256 _nftId,
        uint256 _rentDuration,
        address _collateralAsset
    ) external {
        require(_rentNft != address(0), 'Invalid NFT address');
        require(!quotes[_rentNft][_nftId], 'The quote already exists');
        quoteVarsInfo[_rentNft][_nftId].NFTRent = _rentNft;
        quoteVarsInfo[_rentNft][_nftId].NFTId = _nftId;
        quoteVarsInfo[_rentNft][_nftId].NFTOwner = msg.sender;
        quoteVarsInfo[_rentNft][_nftId].maxRentalDuration = _rentDuration;
        quoteVarsInfo[_rentNft][_nftId].collateralAsset = _collateralAsset;
        quoteVarsInfo[_rentNft][_nftId].expert = address(0);
        quoteVarsInfo[_rentNft][_nftId].verified = false;
        quoteVarsInfo[_rentNft][_nftId].quoteStatus = QuoteStatus.REQUESTED;
        quotes[_rentNft][_nftId] = true;
        // ERC721(_rentNft).name();
        emit QuoteRequested(ERC721(_rentNft).name(),_rentNft,_nftId,_collateralAsset,_rentDuration);
    }

    function CustomQuote(
        address _rentNft,
        uint256 _nftId,
        uint256 _rentDuration,
        address _collateralAsset,
        uint256 _dailyRentalPrice,
        uint256 _repayInterval,
        uint256 _collateralAmount
    ) external {
        require(_rentNft != address(0), 'Invalid NFT address');
        require(!quotes[_rentNft][_nftId], 'The quote already exists');
        quoteVarsInfo[_rentNft][_nftId].NFTRent = _rentNft;
        quoteVarsInfo[_rentNft][_nftId].NFTId = _nftId;
        quoteVarsInfo[_rentNft][_nftId].NFTOwner = msg.sender;
        quoteVarsInfo[_rentNft][_nftId].maxRentalDuration = _rentDuration;
        quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice = _dailyRentalPrice;
        quoteVarsInfo[_rentNft][_nftId].repayInterval = _repayInterval;
        quoteVarsInfo[_rentNft][_nftId].collateralAsset = _collateralAsset;
        quoteVarsInfo[_rentNft][_nftId].collateralAmount = _collateralAmount;
        quoteVarsInfo[_rentNft][_nftId].expert = address(0);
        quoteVarsInfo[_rentNft][_nftId].verified = false;
        quoteVarsInfo[_rentNft][_nftId].quoteStatus = QuoteStatus.FIXED;
        quoteVarsInfo[_rentNft][_nftId].Toescrow = false;
        quoteVarsInfo[_rentNft][_nftId].Towallet = true;
        quotes[_rentNft][_nftId] = true;
        emit QuoteReleased(ERC721(_rentNft).name(),_rentNft,_nftId,_collateralAsset,_rentDuration,_dailyRentalPrice,_collateralAmount);
    }

    function AcceptQuote(address _rentNft, uint256 _nftId) external {
        require(quotes[_rentNft][_nftId], 'The quote does not exists');
        require(quoteVarsInfo[_rentNft][_nftId].NFTOwner == msg.sender, 'Only lender can accept quote');
        require(quoteVarsInfo[_rentNft][_nftId].expert != address(0), 'Expert has not given the quote');
        quoteVarsInfo[_rentNft][_nftId].quoteStatus = QuoteStatus.ACCEPTED;
        quoteVarsInfo[_rentNft][_nftId].verified = true;
        emit QuoteAccepted(_rentNft, quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice);
    }

    function RejectQuote(
        address _rentNft,
        uint256 _nftId,
        uint256 _dailyRentalPrice,
        uint256 _collateralAmount
    ) external {
        require(quotes[_rentNft][_nftId], 'The quote does not exists');
        require(quoteVarsInfo[_rentNft][_nftId].NFTOwner == msg.sender, 'Only lender can accept quote');
        require(quoteVarsInfo[_rentNft][_nftId].expert != address(0), 'Expert has not given the quote');
        quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice = _dailyRentalPrice;
        quoteVarsInfo[_rentNft][_nftId].collateralAmount = _collateralAmount;
        quoteVarsInfo[_rentNft][_nftId].quoteStatus = QuoteStatus.REJECTED;
        quoteVarsInfo[_rentNft][_nftId].verified = false;
        emit QuoteRejected(_rentNft, quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice);
    }

    function stopLending(address _rentNft, uint256 _nftId) external {
        require(bytes32(NFTtoHash[_rentNft][_nftId]).length == 0, 'The requested NFT in currently rented');
        require(quotes[_rentNft][_nftId], 'The quote does not exist');
        require(quoteVarsInfo[_rentNft][_nftId].NFTOwner == msg.sender, 'Only lender can stop lending');
        delete quoteVarsInfo[_rentNft][_nftId];
        quotes[_rentNft][_nftId] = false;
        emit LendingStopped(_rentNft, _nftId);
    }

    function Rent(address _rentNft, uint256 _nftId) external payable {
        require(bytes32(NFTtoHash[_rentNft][_nftId]).length == 0, 'The requested NFT is alreay rented');
        require(quoteVarsInfo[_rentNft][_nftId].quoteStatus != QuoteStatus.REQUESTED, 'The quote has not been received yet');
        require(quoteVarsInfo[_rentNft][_nftId].NFTOwner != msg.sender, 'Lender and borrower cannot be the same');
        NFTRentLineCounter = NFTRentLineCounter + 1;
        bytes32 NFTRentLineHash = keccak256(abi.encodePacked(NFTRentLineCounter));
        NFTtoHash[_rentNft][_nftId] = NFTRentLineHash;
        NFTRentLineInfo[NFTRentLineHash].exists = true;
        NFTRentLineInfo[NFTRentLineHash].currentStatus = NFTRentLineStatus.NOT_CREATED;
        NFTRentLineInfo[NFTRentLineHash].borrower = msg.sender;
        NFTRentLineInfo[NFTRentLineHash].lender = quoteVarsInfo[_rentNft][_nftId].NFTOwner;
        NFTRentLineInfo[NFTRentLineHash].rentalPrice = quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice;
        NFTRentLineInfo[NFTRentLineHash].NftAsset = _rentNft;
        NFTRentLineInfo[NFTRentLineHash].NftId = _nftId;
        NFTRentLineInfo[NFTRentLineHash].collateralAsset = quoteVarsInfo[_rentNft][_nftId].collateralAsset;

        uint256 maxRentalDuration = quoteVarsInfo[_rentNft][_nftId].maxRentalDuration;
        uint256 repayInterval = quoteVarsInfo[_rentNft][_nftId].repayInterval;
        NFTRentLineUsage[NFTRentLineHash].repayments = maxRentalDuration.div(repayInterval);
        NFTRentLineUsage[NFTRentLineHash].repaymentInterval = repayInterval;
        NFTRentLineUsage[NFTRentLineHash].withdrawInterval = 1 days;
        NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted = maxRentalDuration.div(repayInterval);
        NFTRentLineUsage[NFTRentLineHash]._rentalPrice = quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice;

        uint256 collateralAmount = quoteVarsInfo[_rentNft][_nftId].collateralAmount;
        address collateralAsset = quoteVarsInfo[_rentNft][_nftId].collateralAsset;
        depositCollateral(_rentNft, _nftId, collateralAmount);
        NFTRentLineUsage[NFTRentLineHash].loanStartTime = block.timestamp;
        NFTRentLineUsage[NFTRentLineHash].lastRepaymentTime = block.timestamp;
        NFTRentLineInfo[NFTRentLineHash].currentStatus = NFTRentLineStatus.REQUESTED;

        emit RentRequested(_rentNft, NFTRentLineHash, NFTRentLineInfo[NFTRentLineHash].currentStatus);
    }

    function depositCollateral(
        address _rentNft,
        uint256 _nftId,
        uint256 _amount
    ) internal {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        address _collateralAsset = NFTRentLineInfo[NFTRentLineHash].collateralAsset;
        IERC20(_collateralAsset).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function calculateInterest(address _rentNft, uint256 _nftId) internal view returns (uint256 Interest) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        uint256 dailyRent = NFTRentLineUsage[NFTRentLineHash]._rentalPrice;
        uint256 repayInterval = NFTRentLineUsage[NFTRentLineHash].repaymentInterval;
        Interest = dailyRent * repayInterval;
    }

    function SendNft(address _rentNft, uint256 _nftId) external payable onlyNFTRentLineLender(NFTtoHash[_rentNft][_nftId]) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.REQUESTED, 'The Rent has not been requested yet.');
        uint256 _currentTime = block.timestamp;
        uint256 _loanStartTime = NFTRentLineUsage[NFTRentLineHash].loanStartTime;
        uint256 _withdrawInterval = NFTRentLineUsage[NFTRentLineHash].withdrawInterval;
        if (_currentTime <= _loanStartTime.add(_withdrawInterval)) {
            if (quoteVarsInfo[_rentNft][_nftId].Towallet == true) {
                address to = payable(NFTRentLineInfo[NFTRentLineHash].borrower);
                uint256 tokenId = quoteVarsInfo[_rentNft][_nftId].NFTId;
                IERC721(_rentNft).safeTransferFrom(msg.sender, to, tokenId);
            }
            NFTRentLineInfo[NFTRentLineHash].currentStatus = NFTRentLineStatus.ACTIVE;
            NFTRentLineUsage[NFTRentLineHash].lastRepaymentTime = block.timestamp;
            emit RentActive(_rentNft, NFTRentLineHash, NFTRentLineInfo[NFTRentLineHash].currentStatus);
        } else {
            NFTRentLineInfo[NFTRentLineHash].currentStatus = NFTRentLineStatus.CANCELLED;
            emit RentCancelled(_rentNft, NFTRentLineHash, NFTRentLineInfo[NFTRentLineHash].currentStatus);
        }
    }

    function ClaimCollateral(address _rentNft, uint256 _nftId) external onlyNFTRentLineBorrower(NFTtoHash[_rentNft][_nftId]) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.CANCELLED, 'The Rent has not been cancelled yet.');
        uint256 _collateralAmount = quoteVarsInfo[_rentNft][_nftId].collateralAmount;
        _claimCollateral(_rentNft, _nftId, _collateralAmount);
    }

    function _claimCollateral(
        address _rentNft,
        uint256 _nftId,
        uint256 _collateralAmount
    ) internal {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        address _collateralAsset = NFTRentLineInfo[NFTRentLineHash].collateralAsset;
        IERC20(_collateralAsset).safeTransferFrom(address(this), msg.sender, _collateralAmount);
    }

    function RepayNft(address _rentNft, uint256 _nftId) internal {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        require(NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted == 0, 'Please complete remaining repayments first');
        if (quoteVarsInfo[_rentNft][_nftId].Towallet == true) {
            address to = payable(NFTRentLineInfo[NFTRentLineHash].lender);
            uint256 tokenId = quoteVarsInfo[_rentNft][_nftId].NFTId;
            IERC721(_rentNft).safeTransferFrom(msg.sender, to, tokenId);
        }
        NFTRentLineInfo[NFTRentLineHash].currentStatus = NFTRentLineStatus.CLOSED;
        emit RentClosed(_rentNft, NFTRentLineHash, NFTRentLineInfo[NFTRentLineHash].currentStatus);
    }

    function repayInterest(
        address _rentNft,
        uint256 _nftId,
        uint256 _amount
    ) external payable onlyNFTRentLineBorrower(NFTtoHash[_rentNft][_nftId]) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        require(NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted >= 1, 'All repayments are done');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.ACTIVE, 'Renting has not begun yet');
        uint256 Interest = calculateInterest(_rentNft, _nftId);
        require(Interest == _amount, 'Insufficient amount');
        uint256 _currentTime = block.timestamp;
        uint256 _lastRepaymentTime = NFTRentLineUsage[NFTRentLineHash].lastRepaymentTime;
        uint256 _repaymentInterval = NFTRentLineUsage[NFTRentLineHash].repaymentInterval;
        if (_currentTime <= _lastRepaymentTime.add(_repaymentInterval)) {
            if (NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted == 1) {
                _repay(_rentNft, _nftId, _amount);
                RepayNft(_rentNft, _nftId);
            } else {
                _repay(_rentNft, _nftId, _amount);
            }
            NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted = NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted - 1;
            NFTRentLineUsage[NFTRentLineHash].lastRepaymentTime = block.timestamp;
            emit Repaid(_rentNft, NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted);
        } else {
            NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.DEFAULTED;
            emit RentDefaulted(_rentNft, NFTRentLineHash, NFTRentLineInfo[NFTRentLineHash].currentStatus);
        }
    }

    function _repay(
        address _rentNft,
        uint256 _nftId,
        uint256 _amount
    ) internal {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        address _collateralAsset = NFTRentLineInfo[NFTRentLineHash].collateralAsset;
        address _expert = quoteVarsInfo[_rentNft][_nftId].expert;
        if (quoteVarsInfo[_rentNft][_nftId].verified == true) {
            uint256 fees = _amount.mul(expertFee).div(10**30);
            uint256 payment = _amount.sub(fees);
            IERC20(_collateralAsset).safeTransferFrom(msg.sender, address(this), payment);
            IERC20(_collateralAsset).safeTransferFrom(msg.sender, _expert, fees);
        } else {
            IERC20(_collateralAsset).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function liquidateStake(address _rentNft, uint256 _nftId) internal view returns (uint256 stake) {
        require(bytes32(NFTtoHash[_rentNft][_nftId]).length != 0, 'The NFT is not rented');
        stake = quoteVarsInfo[_rentNft][_nftId].collateralAmount.mul(expertStake).div(10**30);
    }

    function claimDeposit(address _rentNft, uint256 _nftId) external onlyNFTRentLineLender(NFTtoHash[_rentNft][_nftId]) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent is not yet requested');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.DEFAULTED, 'The rent is not defaulted yet.');
        address asset = NFTRentLineInfo[NFTRentLineHash].collateralAsset;
        uint256 repaymentsDone = NFTRentLineUsage[NFTRentLineHash].repaymentsCompleted;
        uint256 TotalRepayments = NFTRentLineUsage[NFTRentLineHash].repayments;
        uint256 remainder = TotalRepayments.sub(repaymentsDone);
        uint256 _repaymentAmount = calculateInterest(_rentNft, _nftId);

        uint256 repaymentClaim = _repaymentAmount.mul(remainder);
        uint256 totalClaim = quoteVarsInfo[_rentNft][_nftId].collateralAmount.add(repaymentClaim);

        if (quoteVarsInfo[_rentNft][_nftId].verified == true) {
            uint256 _fees = (_repaymentAmount.mul(expertFee).div(10**30)).mul(remainder);
            uint256 stake = liquidateStake(_rentNft, _nftId);
            totalClaim = totalClaim.add(stake).sub(_fees);
        }
        IERC20(asset).safeTransferFrom(address(this), msg.sender, totalClaim);
    }

    function verifyBorrower(address _borrower) external OnlyExpert(msg.sender) {
        require(!VerifiedBorrowers[_borrower], 'The borrower is already verified');
        // _verifyBorrower(_borrower);
        VerifiedBorrowers[_borrower] = true;
        emit BorrowerVerified(_borrower);
    }

    function provideQuote(
        address _rentNft,
        uint256 _nftId,
        uint256 _dailyRentPrice,
        uint256 _collateralAmount,
        uint256 _repayInterval,
        bool _toescrow,
        bool _towallet
    ) external OnlyExpert(msg.sender) {
        require(_rentNft != address(0), 'Invalid NFT address');
        require(quotes[_rentNft][_nftId], 'The quote does not exist');
        require(quoteVarsInfo[_rentNft][_nftId].quoteStatus == QuoteStatus.REQUESTED,'The quote value exists');
        require(_toescrow != _towallet, 'Both escrow and wallet cannot be set to same value');
        quoteVarsInfo[_rentNft][_nftId].expert = msg.sender;
        quoteVarsInfo[_rentNft][_nftId].verified = true;
        quoteVarsInfo[_rentNft][_nftId].dailyRentalPrice = _dailyRentPrice;
        quoteVarsInfo[_rentNft][_nftId].collateralAmount = _collateralAmount;
        quoteVarsInfo[_rentNft][_nftId].repayInterval = _repayInterval;
        quoteVarsInfo[_rentNft][_nftId].Toescrow = _toescrow;
        quoteVarsInfo[_rentNft][_nftId].Towallet = _towallet;
        emit QuoteProvided(_rentNft, _nftId, _dailyRentPrice, _repayInterval, _collateralAmount);
    }

    function Stake(
        address _rentNft,
        uint256 _nftId,
        uint256 _amount
    ) external payable OnlyExpert(msg.sender) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent line does not exist');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.REQUESTED, 'Rent not requested');
        uint256 stake = quoteVarsInfo[_rentNft][_nftId].collateralAmount.mul(expertStake).div(10**30);
        if (quoteVarsInfo[_rentNft][_nftId].verified == true) {
            require(stake == _amount, 'The amount provided is not correct');
            depositCollateral(_rentNft, _nftId, _amount);
        }
    }

    function ClaimStake(address _rentNft, uint256 _nftId) external OnlyExpert(msg.sender) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent line does not exist');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.CANCELLED, 'Rent not cancelled');
        uint256 stake = quoteVarsInfo[_rentNft][_nftId].collateralAmount.mul(expertStake).div(10**30);
        if (quoteVarsInfo[_rentNft][_nftId].verified == true) {
            _claimCollateral(_rentNft, _nftId, stake);
        }
    }

    function GetStakeBack(address _rentNft, uint256 _nftId) external OnlyExpert(msg.sender) {
        bytes32 NFTRentLineHash = NFTtoHash[_rentNft][_nftId];
        require(NFTRentLineInfo[NFTRentLineHash].exists, 'The NFT rent line does not exist');
        require(NFTRentLineInfo[NFTRentLineHash].currentStatus == NFTRentLineStatus.CLOSED, 'Rent not closed');
        uint256 stake = quoteVarsInfo[_rentNft][_nftId].collateralAmount.mul(expertStake).div(10**30);
        if (quoteVarsInfo[_rentNft][_nftId].verified == true) {
            _claimCollateral(_rentNft, _nftId, stake);
        }
    }
}