pragma solidity >=0.6.0 <0.8.0;
//SPDX-License-Identifier: MIT

interface IVerification {
    function isUser(address _user, address _verifier) external view returns (bool);

    function registerMasterAddress(address _masterAddress, bool _isMasterLinked) external;

    function unregisterMasterAddress(address _masterAddress, address _verifier) external;

    function addVerifier(address _verifier) external;

    function removeVerifier(address _verifier) external;
}