# Escrow

Descrição
---------
Contrato inteligente simples de escrow (depósito em custódia) que mantém fundos até que uma condição seja atendida (liberação para beneficiário) ou cancelamento/estorno ao depositante.

Principais arquivos
-------------------
- `Escrow.sol` — contrato principal de escrow

Funcionalidades
---------------
- Depositar fundos em custódia para um beneficiário
- Liberar fundos para o beneficiário quando a condição for atendida
- Cancelar/estornar fundos de volta ao depositante (quando aplicável)
- Eventos para deposit, release e cancel

Segurança
--------
- Verifique tratamento de reentrância (usar checks-effects-interactions / ReentrancyGuard)
- Validar permissões de quem pode acionar `release` e `cancel`
- Checar limites e proteção contra transações inesperadas

Licença
-------
MIT
