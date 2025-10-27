# CounterOfVotes

Descrição
---------
Contrato de votação simples que permite criar propostas e que contas votem a favor ou contra; contabiliza votos e finaliza resultados.

Principais arquivos
-------------------
- `CounterOfVotes.sol` — contrato principal de votação

Funcionalidades
---------------
- Criar proposta (título, descrição, prazo)
- Votar a favor ou contra uma proposta
- Contabilizar votos e encerrar votação
- Evitar votos duplicados (cada conta vota uma vez por proposta)
- Eventos para criação, votação e encerramento

Uso / Deploy (exemplo)
----------------------
- Criar proposta:
  - chamar `createProposal(string memory title, string memory description, uint256 duration)`
- Votar:
  - chamar `vote(uint256 proposalId, bool support)`
- Finalizar/ver resultado:
  - `getProposal(proposalId)` / `finalizeProposal(proposalId)` (dependendo da implementação)

Segurança / Boas práticas
-------------------------
- Evitar ataques de rejeição/overflows
- Validar quem pode criar propostas (se necessário)
- Considerar extensão para delegação de voto ou ponderação (voting weight)

Licença
-------
MIT
