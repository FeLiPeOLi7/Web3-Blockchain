// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import "contracts/PointsToken.sol";

contract PointsHookDemo{
    PointsToken public immutable pointsToken;

    mapping(address => uint256) public userPoints;
    mapping(bytes32 => uint256) public poolVolume;

    /// @notice Evento emitido quando pontos são distribuídos
    event PointsAwarded(address indexed user, uint256 points, string reason);

    /// @notice Evento emitido quando volume é registrado
    event VolumeRecorded(bytes32 indexed poolId, uint256 volume);

    constructor(PointsToken _pointsToken){
        pointsToken = _pointsToken;
    }

    function _afterSwap(
        address user,
        uint256 swapValue,
        bytes32 poolId
    ) external {
        // Calcular valor do swap em ETH
        // Atualizar volume da pool
        poolVolume[poolId] += swapValue;

        // Calcular pontos baseado no valor do swap
        uint256 points = swapValue;

        if (points > 0) {
            userPoints[user] += points;
            pointsToken.mint(user, points);
            emit PointsAwarded(user, points, "swap");
            emit VolumeRecorded(poolId, swapValue);
        }

    }

    function _afterAddLiquidity(
        address user,
        uint256 liquidityValue,
        bytes32 poolId
    ) external {
        uint256 points = liquidityValue;

        if (points > 0) {
            userPoints[user] += points;
            pointsToken.mint(user, points);
            emit PointsAwarded(user, points, "liquidity");
        }

    }

    /// @notice Retorna o total de pontos de um usuário
    /// @param user Endereço do usuário
    /// @return Total de pontos acumulados
    function getPoints(address user) external view returns (uint256) {
        return userPoints[user];
    }

    /// @notice Retorna o volume total de uma pool
    /// @param poolId ID da pool
    /// @return Volume total em wei (ETH)
    function getPoolVolume(bytes32 poolId) external view returns (uint256) {
        return poolVolume[poolId];
    }
}