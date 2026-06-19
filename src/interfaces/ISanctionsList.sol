// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <contact@kiln.fi>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.22;

/// @title Sanctions List Interface.
/// @notice Interface for the sanctions list contract from Chainalysis.
interface ISanctionsList {
    /// @notice Check if an address is sanctioned.
    /// @param addr The address to check.
    /// @return True if the address is sanctioned, false otherwise.
    function isSanctioned(address addr) external view returns (bool);

    /// @notice Add addresses to the sanctions list.
    /// @param newSanctions The addresses to add.
    function addToSanctionsList(address[] memory newSanctions) external;

    /// @notice Remove addresses from the internal sanctions list.
    /// @param sanctions The addresses to remove.
    function removeFromSanctionsList(address[] memory sanctions) external;
}
