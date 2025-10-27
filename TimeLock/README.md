
Descrição
---------
Contrato de TimeLock que bloqueia fundos (ETH ou tokens) até uma data/tempo ou bloco específico. Util para governança, liberação programada de fundos e vesting.

Principais arquivos
-------------------
- `TimeLock.sol` — contrato principal de time lock


Funcionalidades
---------------
- Bloquear fundos por um período (timestamp ou número de blocos)
- Retirar fundos somente após o tempo de liberação
- Possibilidade de múltiplos lockers por usuário
- Eventos para criação e liberação de lock

Uso / Deploy (exemplo)
----------------------
- Criar lock:
  - chamar função `lock(address tokenOrZeroForETH, uint256 amount, uint256 releaseTimestamp)`
- Retirar:
  - chamar `withdraw(lockId)` após `releaseTimestamp`
- Deploy local:
  - npx hardhat run scripts/deploy.js --network localhost


Segurança
--------
- Validar overflow/underflow (usar compilador recente/OpenZeppelin)
- Proteger funções administrativas (se houver)
- Garantir que tokens ERC20 sejam manipulados com safeTransfer

Licença
-------
MIT
