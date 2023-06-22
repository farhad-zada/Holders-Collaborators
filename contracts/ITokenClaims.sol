// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITokenClaims {
  function setAllocations(address[] calldata _beneficiaries, uint256[] calldata amounts, bool add) external;
}
