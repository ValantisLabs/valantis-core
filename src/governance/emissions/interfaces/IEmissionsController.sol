// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEmissionsController {
    function calculateGaugeEmissions(address _gauge) external returns (uint256 emissions);

    function claimEmissions() external;

    function burnVal() external;

    function getClaimable(address _gauge) external view returns (uint256);

    function setWeeklyEmissionsCapBips(uint256 epochEmissionsCapBips) external;

    function getWeeklyEmissionsCap() external returns (uint256);
}
