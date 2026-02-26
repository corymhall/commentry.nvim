# Question Triage: codex-integration

## Scope Summary
- Scope: P0+P1 only (`Q1..Q124`).
- Questions in scope: **124**.
- Auto-answerable: **101**.
- Human branch decisions: **23**.
- Branch IDs (fixed): `Q5, Q16, Q25, Q27, Q28, Q36, Q50, Q54, Q56, Q57, Q60, Q63, Q68, Q81, Q84, Q89, Q92, Q98, Q102, Q103, Q120, Q121, Q122`.

## Normalization
- Numbering is already sequential and preserved: `Q1..Q124` (no remap needed).

## Auto-Answerable Questions
| Question(s) | Proposed Auto Answer Direction | Rationale | Source |
| --- | --- | --- | --- |
| Q2, Q18, Q29, Q40 | Distinguish transport vs execution state (`sent` vs `acted on`) with explicit status copy. | Required for trust and loop-closure; can be standardized without strategy fork. | UX consistency baseline from scoped prompts. |
| Q8, Q9, Q10, Q20, Q21 | Treat review history as ordered context; show latest plus recoverable prior attempts. | Supports iterative review behavior already implied across journey questions. | UX continuity baseline from scoped prompts. |
| Q52 | File reviewed status is per-file boolean signal; expose as lightweight hint, not full semantic override. | Existing model is strictly boolean toggled state. | `lua/commentry/comments.lua:1131`, `lua/commentry/comments.lua:1132` |
| Q55, Q62, Q67 | Minimum payload includes identity, scope, and traceable link to source context. | Needed for trustworthy actionability and traceability without policy choice. | Context identity is stable in diff context model. `lua/commentry/diffview.lua:251`, `lua/commentry/diffview.lua:252`, `lua/commentry/diffview.lua:254` |
| Q69, Q70, Q73, Q74, Q79, Q80 | Provide idempotency-ish UX + recoverable retry/error states + misunderstanding recovery affordance. | Standard resilience behavior; no product strategy fork required. | Reliability baseline for send flows. |
| Q81-adjacent autos: Q82, Q83, Q86, Q87, Q90, Q91 | Keep default grouping/scanning/provenance vocabulary simple and consistent with existing stored artifacts. | IA defaults can be inferred from existing store/export primitives; single-source naming decision is separate branch (Q81). | Store path and export are already concrete. `lua/commentry/store.lua:254`, `lua/commentry/store.lua:255`, `lua/commentry/store.lua:308`, `lua/commentry/commands.lua:152`, `lua/commentry/comments.lua:1321` |
| Q93, Q95, Q96, Q97, Q99, Q100, Q101, Q104 | Define happy-path/recovery loops around attach -> preview -> send -> verify -> iterate. | Flow mechanics are straightforward once branch strategy is set. | Product flow baseline from scoped prompts. |
| Q105, Q106, Q107, Q108, Q109, Q111, Q114 | Domain edge handling: stale/duplicate/conflicting/multi-commit comments should be surfaced and recoverable. | Domain-safe defaults; does not pick integration strategy. | Domain consistency baseline. |
| Q115, Q116, Q117, Q118, Q119, Q123, Q124 | Measure effort reduction, intent preservation, trust, completion, and turnaround with explicit metrics + user feedback. | Success instrumentation is required regardless of integration point. | Evaluation baseline from success-criteria prompts. |

## Branch Points (Human Decision Required)
| ID | Decision Theme | Why Human Needed |
| --- | --- | --- |
| Q5 | Mandatory vs optional review guidance | Product promise/risk tradeoff: strict enforcement increases safety but may reduce flow speed. |
| Q16 | Multi-session routing cues | Requires UX/mental-model choice for session targeting in concurrent workflows. |
| Q25 | Primary send action | Core interaction contract choice affects discoverability and speed. |
| Q27 | Scope granularity control | Tradeoff between precision and cognitive load; impacts power-user vs default behavior. |
| Q28 | Attach-context vs request-action framing | Strategic positioning decision changes user expectation of agent behavior. |
| Q36 | Sidekick-style framing semantics | Must choose whether interaction is chat, automation invoke, or hybrid. |
| Q50 | Semantics of comments (instruction/constraint/prompt) | Determines agent interpretation policy and conflict handling. |
| Q54 | Guidance horizon (turn/session/workstream) | Scope-of-effect policy impacts persistence and stale handling. |
| Q56 | Advisory vs blocking modes | Governance/safety model choice with strong workflow implications. |
| Q57 | Plain-language user promise | Marketing/product contract decision; cannot be inferred from code. |
| Q60 | Core problem framing | Strategy alignment choice: transport vs intent vs outcome loop. |
| Q63 | Solo vs team optimization | Persona prioritization affects IA and collaboration investment. |
| Q68 | Beads role in mental model | Determines integration depth and artifacts exposed to users. |
| Q81 | Single source of truth for review | Foundational IA choice across comments/file-flags/export/session state. |
| Q84 | Evolving packet vs immutable snapshots | Versioning/auditability tradeoff; affects state model + UX clarity. |
| Q89 | Unified vs separated spaces | Information architecture boundary decision with workflow cost tradeoffs. |
| Q92 | Durable memory vs temporary guidance boundary | Retention/scope policy decision across sessions. |
| Q98 | Review-to-beads conversion flow | Integration strategy choice; impacts execution continuity and complexity. |
| Q102 | Summarize-only branch flow | Must decide if non-action mode is first-class and where it diverges. |
| Q103 | Multi-person collaboration flow | Ownership/conflict/provenance strategy requires explicit policy. |
| Q120 | Initial target user segments | Go-to-market sequencing and risk management choice. |
| Q121 | Minimum viable sidekick integration | Scope cut line for v1 value vs implementation cost. |
| Q122 | Beads-linked proof artifact | Defines what evidence counts as planning/execution continuity. |

## Question Dependencies
- Foundation semantics first: `Q60 -> Q57 -> Q5/Q50/Q56`.
- Session model next: `Q54 -> Q92 -> Q84`.
- UX contract layer: `Q25/Q28/Q36 -> Q27/Q16`.
- Architecture split: `Q81 -> Q89 -> Q103`.
- Beads strategy chain: `Q68 -> Q98 -> Q122`.
- Delivery framing: `Q63 -> Q120 -> Q121`.
- Summarize-only branch depends on interaction model: `Q28/Q36 -> Q102`.

## Interview Plan
Target burden: ~10 grouped decisions (covers all 23 branch IDs).

1. **Problem + promise**: `Q60, Q57`.
2. **Governance policy**: `Q5, Q50, Q56`.
3. **Session horizon + memory**: `Q54, Q92, Q84`.
4. **Primary interaction contract**: `Q25, Q28, Q36`.
5. **Targeting + scope control**: `Q16, Q27`.
6. **Information architecture spine**: `Q81, Q89`.
7. **Collaboration posture**: `Q63, Q103`.
8. **Beads integration depth**: `Q68, Q98, Q122`.
9. **Summarize-only branch**: `Q102`.
10. **Launch focus + floor**: `Q120, Q121`.

## Detailed Classification (Q1..Q124)
| # | Tier | Category | Decision | Source/Reason |
| --- | --- | --- | --- | --- |
| Q1 | P0 | User Expectations | Auto | Expected immediate post-save/send response can be standardized UX baseline. |
| Q2 | P0 | User Expectations | Auto | Transport vs acted-on status separation is a standard trust requirement. |
| Q3 | P0 | User Expectations | Auto | Acknowledgment level can default to confirmation + next step hint. |
| Q4 | P0 | User Expectations | Auto | Near-term influence expectation can be set by explicit status timing. |
| Q5 | P0 | User Expectations | Branch | Product policy choice: mandatory guidance vs optional context. |
| Q6 | P0 | User Expectations | Auto | User control timing can default to explicit send action. |
| Q7 | P0 | User Expectations | Auto | Confidence signals can default to status + linked provenance. |
| Q8 | P0 | User Expectations | Auto | Multiple reviews handled via ordered, visible history. |
| Q9 | P0 | User Expectations | Auto | History depth can default to current + recent relevant context. |
| Q10 | P0 | User Expectations | Auto | Revision handling can auto-mark superseded and preserve trace. |
| Q11 | P0 | User Expectations | Auto | Pre-send ambiguity warnings are a standard quality guardrail. |
| Q12 | P0 | User Expectations | Auto | Transparency can be shown via mapping review->action/result. |
| Q13 | P0 | User Journey | Auto | Most likely send moment can default near review completion checkpoint. |
| Q14 | P0 | User Journey | Auto | Simplest path is select -> preview -> send -> observe status. |
| Q15 | P0 | User Journey | Auto | Discovery can use first-use inline hints/tooling affordance. |
| Q16 | P0 | User Journey | Branch | Multi-session disambiguation model is a UX strategy choice. |
| Q17 | P0 | User Journey | Auto | Pre-confirmation steps can be minimal with preview summary. |
| Q18 | P0 | User Journey | Auto | Progress states (pending/received/acted) are a standard loop. |
| Q19 | P0 | User Journey | Auto | Edit/retract/resend can live in sent-item actions. |
| Q20 | P0 | User Journey | Auto | Prior review comparison via timestamped attempts is straightforward. |
| Q21 | P0 | User Journey | Auto | Leave-return continuity uses persisted local context. |
| Q22 | P0 | User Journey | Auto | Team handoff can preserve provenance fields in payload. |
| Q23 | P0 | User Journey | Auto | Unavailable agent path can queue/retry with clear failure state. |
| Q24 | P0 | User Journey | Auto | Completion can use explicit lifecycle-done indicator. |
| Q25 | P0 | Interaction Design | Branch | Primary send affordance defines core UX contract. |
| Q26 | P0 | Interaction Design | Auto | Confirmation detail can default to scope + target + mode. |
| Q27 | P0 | Interaction Design | Branch | Scope granularity control is a precision-vs-speed product tradeoff. |
| Q28 | P0 | Interaction Design | Branch | Attach vs request-action framing sets expectation semantics. |
| Q29 | P0 | Interaction Design | Auto | Success link state can be explicit and persistent. |
| Q30 | P0 | Interaction Design | Auto | Pre-send curation can use lightweight selection/edit panel. |
| Q31 | P0 | Interaction Design | Auto | Quick follow-up actions are additive defaults after send. |
| Q32 | P0 | Interaction Design | Auto | Undo/retract can be modeled as supersede action. |
| Q33 | P0 | Interaction Design | Auto | Stale/superseded detection and rebase prompt are standard. |
| Q34 | P0 | Interaction Design | Auto | Expert speed + first-use guidance can be balanced with progressive disclosure. |
| Q35 | P0 | Interaction Design | Auto | Multi-send chaining can be supported with pacing/status cues. |
| Q36 | P0 | Interaction Design | Branch | Sidekick framing (message/invoke/hybrid) is strategic product semantics. |
| Q37 | P0 | States & Transitions | Auto | Minimum explicit states are definable from flow requirements. |
| Q38 | P0 | States & Transitions | Auto | Large bundle progress transitions are standard async UX behavior. |
| Q39 | P0 | States & Transitions | Auto | Mid-flow unavailable session should shift to recoverable failure state. |
| Q40 | P0 | States & Transitions | Auto | Distinguish sent vs acted-on to preserve trust. |
| Q41 | P0 | States & Transitions | Auto | Changed-after-send should create superseded transition. |
| Q42 | P0 | States & Transitions | Auto | Pending edits can be staged for next send snapshot. |
| Q43 | P0 | States & Transitions | Auto | Partial success language can be standardized at item granularity. |
| Q44 | P0 | States & Transitions | Auto | Stale marking with recovery action is standard consistency behavior. |
| Q45 | P0 | States & Transitions | Auto | Transient confirmation vs persistent status is straightforward UX split. |
| Q46 | P0 | States & Transitions | Auto | Agent response to tracked-work bridge can be a direct follow-up action. |
| Q47 | P0 | States & Transitions | Auto | "Acknowledged/no action" can be explicit terminal subtype. |
| Q48 | P0 | States & Transitions | Auto | Lifecycle-done with reopen support is a standard completion model. |
| Q49 | P0 | Domain Concepts | Auto | Primary job is converting review signal into actionable context. |
| Q50 | P0 | Domain Concepts | Branch | Comment semantics (instruction/constraint/prompt) requires policy choice. |
| Q51 | P0 | Domain Concepts | Auto | Draft->resolved lifecycle can be normalized with status transitions. |
| Q52 | P0 | Domain Concepts | Auto | File reviewed is per-file boolean state toggle. `lua/commentry/comments.lua:1131`, `lua/commentry/comments.lua:1132` |
| Q53 | P0 | Domain Concepts | Auto | Comment type weighting can default by severity/actionability heuristics. |
| Q54 | P0 | Domain Concepts | Branch | Turn/session/workstream scope is a strategic horizon decision. |
| Q55 | P0 | Domain Concepts | Auto | Minimum trustworthy context includes stable review identity fields from context construction. `lua/commentry/diffview.lua:251`, `lua/commentry/diffview.lua:252`, `lua/commentry/diffview.lua:254` |
| Q56 | P0 | Domain Concepts | Branch | Advisory vs blocking mode is governance/product policy. |
| Q57 | P0 | Domain Concepts | Branch | Plain-language integration promise is a product contract decision. |
| Q58 | P0 | Domain Concepts | Auto | Multi-author ownership can be represented with provenance metadata. |
| Q59 | P0 | Problem Depth | Auto | Current pain can be stated as stored-but-not-live reuse gap. |
| Q60 | P0 | Problem Depth | Branch | Core problem framing determines strategy and prioritization. |
| Q61 | P0 | Problem Depth | Auto | Re-explanation frequency can be treated as baseline metric to capture. |
| Q62 | P0 | Problem Depth | Auto | Traceability expectation can be met with context_id + status linkage. `lua/commentry/diffview.lua:251`, `lua/commentry/diffview.lua:252`, `lua/commentry/diffview.lua:254` |
| Q63 | P0 | Problem Depth | Branch | Persona optimization (solo/team) is strategic focus decision. |
| Q64 | P0 | Problem Depth | Auto | Conflicting comments can be surfaced pre-send with explicit conflict marker. |
| Q65 | P0 | Problem Depth | Auto | False-positive cost can be treated as quality risk KPI. |
| Q66 | P0 | Problem Depth | Auto | Active corpus can default to current context + selected relevant history. |
| Q67 | P0 | Problem Depth | Auto | Turnaround expectation can be explicit SLA target in UX copy/metrics. |
| Q68 | P0 | Problem Depth | Branch | Beads mental-model role is product strategy choice. |
| Q69 | P1 | Edge Cases | Auto | Duplicate sends should be detectable and recoverable. |
| Q70 | P1 | Edge Cases | Auto | Conflicting self-reviews can be ordered by recency with supersede markers. |
| Q71 | P1 | Edge Cases | Auto | Team disagreement can be surfaced as conflict set before send. |
| Q72 | P1 | Edge Cases | Auto | Wrong-target send recovery can support retract/resend with clear audit trail. |
| Q73 | P1 | Edge Cases | Auto | Partial/interrupt states should support retry/resume. |
| Q74 | P1 | Edge Cases | Auto | Overlong/vague content should trigger guidance and trimming prompts. |
| Q75 | P1 | Edge Cases | Auto | Late review after completion can be marked informational/deferred. |
| Q76 | P1 | Edge Cases | Auto | Sensitive data mis-send needs redact + warning + safe handling path. |
| Q77 | P1 | Edge Cases | Auto | Rapid task switching requires persistent context indicators. |
| Q78 | P1 | Edge Cases | Auto | Emotional/unclear language should route through clarification prompts. |
| Q79 | P1 | Edge Cases | Auto | Unclear usage should be resolved via explicit status/provenance trail. |
| Q80 | P1 | Edge Cases | Auto | Misunderstanding recovery needs revise-and-resend loop. |
| Q81 | P1 | Information Architecture | Branch | Source-of-truth architecture across comments/flags/export/session is foundational IA choice. |
| Q82 | P1 | Information Architecture | Auto | Grouping defaults (file/thread/severity/status) can be standardized. |
| Q83 | P1 | Information Architecture | Auto | Essential default fields can be set via progressive disclosure norms. |
| Q84 | P1 | Information Architecture | Branch | Mutable packet vs immutable snapshots is versioning/auditability strategy. |
| Q85 | P1 | Information Architecture | Auto | Draft vs trusted finding distinction can be represented by status/type. |
| Q86 | P1 | Information Architecture | Auto | Vocabulary standardization can be resolved via controlled labels. |
| Q87 | P1 | Information Architecture | Auto | Intent buckets mapping can be explicit metadata. |
| Q88 | P1 | Information Architecture | Auto | Local context vs prior-art hierarchy can default local-first with references. |
| Q89 | P1 | Information Architecture | Branch | Unified vs separate spaces is major IA/workflow boundary choice. |
| Q90 | P1 | Information Architecture | Auto | Provenance metadata set is straightforward and low-risk. |
| Q91 | P1 | Information Architecture | Auto | "Resolved" language can be standardized with explicit sub-states. |
| Q92 | P1 | Information Architecture | Branch | Durable vs temporary memory boundary is retention policy decision. |
| Q93 | P1 | User Flows | Auto | Happy path can follow attach->preview->send->act->verify pattern. |
| Q94 | P1 | User Flows | Auto | Scope selection point can default during preview with quick preselect. |
| Q95 | P1 | User Flows | Auto | No-session vs active-session flow can branch with same final status model. |
| Q96 | P1 | User Flows | Auto | Wrong-send recovery flow can use retract/supersede actions. |
| Q97 | P1 | User Flows | Auto | Back-link from response to source artifacts is direct traceability requirement. |
| Q98 | P1 | User Flows | Branch | Beads conversion path is explicit integration strategy decision. |
| Q99 | P1 | User Flows | Auto | Mixed review types can be normalized into one payload schema. |
| Q100 | P1 | User Flows | Auto | Onboarding can be lightweight and dismissible by design. |
| Q101 | P1 | User Flows | Auto | Repeated usage can adapt via remembered preferences. |
| Q102 | P1 | User Flows | Branch | Summarize-only branch requires explicit non-action product choice. |
| Q103 | P1 | User Flows | Branch | Multi-person collaboration policy requires ownership/conflict decisions. |
| Q104 | P1 | User Flows | Auto | End-of-flow completion signal can be explicit processed state. |
| Q105 | P1 | Edge Cases (Domain) | Auto | Obsolete comments should be marked stale pre-handoff. |
| Q106 | P1 | Edge Cases (Domain) | Auto | Duplicate concerns can be clustered with representative item. |
| Q107 | P1 | Edge Cases (Domain) | Auto | File-reviewed with unresolved issues should show mixed state indicator. |
| Q108 | P1 | Edge Cases (Domain) | Auto | Contradictory instructions should trigger conflict resolution prompt. |
| Q109 | P1 | Edge Cases (Domain) | Auto | Multi-commit intent drift should preserve timeline and recency. |
| Q110 | P1 | Edge Cases (Domain) | Auto | Praise-only reviews can be tagged informational/no-action. |
| Q111 | P1 | Edge Cases (Domain) | Auto | Partial automation suitability should split actionable vs human-review buckets. |
| Q112 | P1 | Edge Cases (Domain) | Auto | Sensitive/policy comments need safe-mode handling by default. |
| Q113 | P1 | Edge Cases (Domain) | Auto | Divergent response should trigger compare-and-correct loop. |
| Q114 | P1 | Edge Cases (Domain) | Auto | Cross-file themes can be represented as thematic findings linked to lines. |
| Q115 | P1 | Success Criteria | Auto | Effort reduction outcome can be measured with time/steps saved. |
| Q116 | P1 | Success Criteria | Auto | Intent preservation evidence can be measured via trace mapping quality. |
| Q117 | P1 | Success Criteria | Auto | Trust increase can be measured against copy-paste baseline behavior. |
| Q118 | P1 | Success Criteria | Auto | Fully acted-on signal can be represented with completion criteria state. |
| Q119 | P1 | Success Criteria | Auto | Acceptable misinterpretation rate can be set as product quality threshold. |
| Q120 | P1 | Success Criteria | Branch | Initial segment prioritization is GTM/risk strategy choice. |
| Q121 | P1 | Success Criteria | Branch | Minimum sidekick integration value floor is release-scope decision. |
| Q122 | P1 | Success Criteria | Branch | Beads-linked proof artifact defines what counts as continuity evidence. |
| Q123 | P1 | Success Criteria | Auto | Turnaround improvement target can be set as measurable KPI. |
| Q124 | P1 | Success Criteria | Auto | Qualitative habit-change signals can be captured via user feedback prompts. |
