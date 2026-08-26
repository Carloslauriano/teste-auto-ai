# Coding Standards

<!-- Baseado no SaaS Panel Design System (base-ui-saas: DESIGN.md, INSTALLATION.md, REVIEWER.md).
     Stack: React + TypeScript + Tailwind CSS + shadcn/ui.
     O reviewer agent carrega este arquivo via @.sandcastle/CODING_STANDARDS.md
     durante o code review. -->

## Style

- Cor sempre via token CSS em triplo HSL puro (`142 56% 31%`) — nunca `hsl()`, nunca vírgulas, nunca hex literal no componente. Acentos não-semânticos só vêm do vocabulário fechado: `emerald`, `sky`, `violet`, `amber`, `rose`, `primary`.
- Acento sólido no dark mode sempre usa `dark:*-primary-glow` (nunca `primary` sólido no dark); preenchimentos translúcidos (`bg-primary/10`) continuam com `primary`.
- Tipografia só Inter, pesos 400/500/600/700 — headings diferem por peso/tamanho, nunca por família.
- Números comparáveis verticalmente levam `tabular-nums`, formatados via `Intl` no locale do app; valor ausente renderiza `—`, nunca `0` / `R$ 0,00` / `0%`.
- Densidade padrão: controles (`button`/`input`/`select`) `h-9`, `table thead` `h-10`, linha de tabela ~52px, `card` `rounded-xl border-border/60`, modal `max-h-[88vh]` com scroll no corpo, container de página `space-y-6` (dashboard `space-y-4`). Ícones `w-4 h-4` em botões, `w-5 h-5` standalone.
- Separação visual vem de bordas, não de sombra (`hover:shadow-sm` é o máximo que um card recebe).
- Texto em flex sempre com `min-w-0` no pai + `truncate`; ícones adjacentes levam `shrink-0`.
- Nunca edite `components/ui/**` à mão — são os primitivos gerados pelo `shadcn` CLI. Customização entra como diff documentado (ver Arquitetura) ou como wrapper em `components/`.
- Todo componente shadcn novo entra via `npx shadcn@latest add <componente>` — nunca copiado/colado manualmente do site.
- Estado escolhido pelo usuário (aba, view, período) vive na URL (`?tab=`, `?view=`, `?period=`), não só em state local.

## Testing

- Rode `npx tsc --noEmit`, `npm run lint` e `npm run build` antes de considerar qualquer tela pronta.
- Verifique visualmente: `bg-primary/10` renderiza tint translúcido da marca; alternar `.dark` no `<html>` troca a paleta inteira; `<Button>` tem 36px de altura; `<Card>` tem raio de 12px e borda suave; cabeçalho de tabela é uppercase/pequeno/muted.
- Toda tela cobre os quatro estados obrigatórios — `loading → error → empty → content` — e isso é parte do critério de "pronto", não um nice-to-have.
- Estado de erro sempre tem retry visível; nunca falha silenciosa.
- Nunca faça early-return de estado vazio que substitua a tela inteira (esconde header/KPIs/filtros) — teste que os filtros continuam acessíveis com lista vazia.
- Ação destrutiva sempre passa por `AlertDialog` nomeando o registro e a consequência — nunca `window.confirm` nem exclusão silenciosa; isso deve ser coberto ao testar o fluxo.
- Ação bloqueada fica desabilitada com `Tooltip` explicando o motivo — nunca escondida; verifique isso manualmente antes do PR.

## Architecture

- Uma solução por problema — sem variação local para o mesmo caso de uso. Ver tabela de decisões não-negociáveis abaixo; violar uma delas é bloqueio de review.

  | Problema | A única resposta | Nunca |
  |---|---|---|
  | Sub-navegação dentro de uma página | `<PageSubnav>` (rail lateral) | `<Tabs>` |
  | Mostrar detalhes de um registro | `<DetailModal>` (modal + sidebar de seções) | `<Sheet>` / drawer |
  | Editar campos de um registro | `<InlineField>` no local onde o valor é lido | aba "Editar" ou segundo modal |
  | Tela de listagem tabular | `PageHeader` → `StatsGrid` → filter `Card` → `ListCard` | `PAGE_SIZE` fixo, coluna "Projeto/Tenant" redundante |
  | Card-portal para outras rotas | `<HubPage>` | grid de `<Card>` improvisado |
  | Selecionar de lista que cresce | combo pesquisável (`Popover` + `Command`) | `<Select>` com dezenas de itens |
  | Subir na hierarquia | breadcrumb do shell | botão "Voltar" na página |
  | Ação destrutiva | `AlertDialog` nomeando o registro | `window.confirm` |
  | Ação bloqueada | botão desabilitado + `Tooltip` com o motivo | esconder o botão |
  | Gráfico / KPI | `<ChartCard>` / `<KpiCard>` do `DashboardKit` | Recharts cru dentro de um `<Card>` |

- Pipeline de listas é sempre `filter → sort → paginate`, nessa ordem, com ordenação sobre a lista inteira antes de paginar. `resetPage()` roda quando filtro **ou** ordenação mudam.
- Paginação é sempre adaptativa via `usePagination(items, { auto: true })` medindo o container real (callback ref, nunca `useRef` + effect) — jamais um `PAGE_SIZE` fixo.
- Busca usa debounce de 300ms: o valor cru alimenta o input, o valor debounced alimenta o filtro.
- Toasts vivem no hook de dados, não no componente (uma ação, um toast).
- Primitivos shadcn (`button`, `card`, `input`/`textarea`/`select`, `table`, `dialog`) seguem os diffs padronizados do design system (`h-9` em controles, `rounded-xl border-border/60 p-5` em card, focus ring `ring-primary/20`, `p-5 gap-3` em dialog); `badge` e o restante ficam stock.
- Acessibilidade é parte da arquitetura, não um retrofit: elementos interativos são `<button>`/`<a>` (nunca `<div onClick>`), controles só-ícone têm `aria-label`/`title`, item de navegação ativo leva `aria-current="page"`, focus ring nunca é removido sem substituto, cor nunca é o único canal carregando significado.
