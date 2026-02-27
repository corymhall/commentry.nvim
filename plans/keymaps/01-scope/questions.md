# Keymaps Final Question Backlog

Model-lane usage:
- Used: `codex-questions.md` (all active questions included).
- Excluded: `claude-questions.md` and `gemini-questions.md` (both files are marked `Skipped`).
- Attribution format: `[codex]` indicates which model lane contributed each question.

Totals:
- Raw questions: 140
- Unique after dedupe: 140
- P0: 40
- P1: 50
- P2: 30
- P3: 20
- Check: P0 + P1 + P2 + P3 = 140

## P0 (1-40)
1. [codex] Which actions do users expect to have default keymaps immediately after setup?
2. [codex] Do users expect every function to be mappable, or only frequently used ones?
3. [codex] How strongly do users expect keymaps to match common Neovim conventions?
4. [codex] What level of discoverability do users expect for available keymapped actions?
5. [codex] Do users expect keymaps to work consistently across all review sessions and repositories?
6. [codex] How much do users care about preserving their existing personal keybinding habits?
7. [codex] Do users expect to disable individual mappings without disabling the related feature?
8. [codex] What response do users expect when a configured mapping cannot be used as intended?
9. [codex] Do users expect distinct mappings for similar actions to avoid accidental misuse?
10. [codex] How important is it that defaults feel safe for beginners while still efficient for power users?
11. [codex] At what moment in onboarding should users first learn that keymaps are customizable?
12. [codex] What is the first keymapping change a typical user is likely to make?
13. [codex] How do users decide whether to keep defaults or customize immediately?
14. [codex] What steps do users take to verify that a new mapping behaves as expected?
15. [codex] When users return after time away, how do they recall their configured mappings?
16. [codex] In daily review flow, which mapped actions are used most often and in what order?
17. [codex] What usually triggers users to revisit and refine their mappings later?
18. [codex] How do users recover when a mapping change breaks their expected routine?
19. [codex] Do users configure mappings once globally or evolve them per project context?
20. [codex] What does a “successful keymap setup” look like from the user’s perspective after one week?
21. [codex] What happens when users intentionally leave some functions unmapped?
22. [codex] How should the experience feel when users map multiple actions too similarly and forget distinctions?
23. [codex] What should users expect after copy-pasting a shared mapping setup that does not match their habits?
24. [codex] How do users behave when they frequently switch between different keyboard layouts?
25. [codex] How should users recover if they cannot remember what they changed from defaults?
26. [codex] What experience should users have if they customize only a subset of functions and ignore the rest?
27. [codex] How should users handle situations where two preferred mappings collide with their broader editor habits?
28. [codex] What should happen when teams recommend one mapping style but individuals prefer another?
29. [codex] How do users respond if they accidentally trigger a destructive action via a too-convenient mapping?
30. [codex] What expectations do users have when they migrate from another commenting/review workflow?
31. [codex] What keymapping needs do users with limited hand mobility or repetitive strain concerns have?
32. [codex] How can users with one-handed workflows configure mappings that remain practical?
33. [codex] What do users who rely on alternative keyboard hardware expect from configurable mappings?
34. [codex] How should mapping guidance support users who are new to modal editing concepts?
35. [codex] What assumptions about language or keyboard region could exclude international users?
36. [codex] How can users with cognitive load concerns keep mappings simple and memorable?
37. [codex] What expectations do screen reader users have for understanding available actions and shortcuts?
38. [codex] How should users be supported when they cannot use multi-key chords comfortably?
39. [codex] What kind of feedback do users need to confirm they triggered the intended action?
40. [codex] How can teams document and share accessible mapping conventions without enforcing a single style?

## P1 (41-90)
41. [codex] Which user actions are considered core enough to always deserve a default keymap? This defines the baseline mental model and prevents overloading users with low-value bindings.
42. [codex] Should keymaps be grouped by intent (comment creation, editing, navigation, review status) in docs and settings?
43. [codex] Do users need separate keymap concepts for line comments versus range comments?
44. [codex] Should command names and keymap labels use the same language as user-facing command menus?
45. [codex] Is there a minimum set of actions that must remain accessible even if users disable most keymaps?
46. [codex] Should navigation-related actions be treated as a separate keymap section from comment actions?
47. [codex] How should optional actions be presented so users can understand they are not required?
48. [codex] Should keymap customization be framed as per-function assignment or preset profiles?
49. [codex] What terminology should be used for “reviewed” status actions to match user expectations?
50. [codex] Should the product distinguish between global plugin keymaps and context-specific keymaps in user education?
51. [codex] What should happen when a user invokes a keymap that is currently unavailable in context?
52. [codex] Should keymap-triggered actions provide immediate confirmation, and if so at what verbosity?
53. [codex] How should users discover available keymaps while actively reviewing a diff?
54. [codex] Should there be a clear distinction between destructive and non-destructive key-triggered actions?
55. [codex] Should repeated use of the same keymap follow a toggle model or explicit one-way actions?
56. [codex] How should interaction behave when two actions feel adjacent, like edit and type change?
57. [codex] Should keymaps prioritize speed for power users or explicitness for occasional users by default?
58. [codex] How should the product communicate conflicts when users choose overlapping key combinations?
59. [codex] Should keymaps trigger multi-step actions expose progress feedback during execution?
60. [codex] Should there be interaction-level affordances for undoing accidental key-triggered actions?
61. [codex] What is the ideal first-run flow for users who want to customize keymaps immediately?
62. [codex] How should a user move from discovering a missing mapping to successfully assigning one?
63. [codex] What is the expected flow when a user switches between reviewing and commenting tasks?
64. [codex] Should users be guided to configure only frequently used actions first?
65. [codex] How should users verify that a custom keymap assignment actually works in the right context?
66. [codex] What is the flow for temporarily disabling a mapping without losing preferred settings?
67. [codex] How should users recover when a configured keymap stops matching their habits over time?
68. [codex] Should there be a recommended flow for teams sharing a common keymap convention?
69. [codex] How does a user transition from command-driven usage to keymap-driven usage over time?
70. [codex] What happens in the user flow when multiple actions could apply to the same selection?
71. [codex] Where should keymap options be presented so they are easy to find but not visually noisy?
72. [codex] Should keymap information be shown inline with actions or in a consolidated reference view?
73. [codex] How should enabled, disabled, and unassigned mappings be visually differentiated?
74. [codex] Should destructive actions have stronger visual emphasis in keymap references?
75. [codex] How should long or complex key combinations be displayed for readability?
76. [codex] Should contextual hints appear near comment markers, command list views, or both?
77. [codex] How dense should keymap reference content be in constrained spaces like floating windows?
78. [codex] Should the layout prioritize alphabetical ordering or workflow ordering of actions?
79. [codex] How should visual design indicate when a mapping only works in specific modes or contexts?
80. [codex] Should keymap customization surfaces emphasize defaults versus user overrides visually?
81. [codex] What distinct states should keymap assignments have (default, customized, disabled, conflicted)?
82. [codex] How should the UI communicate transition from valid to conflicted mapping after a new assignment?
83. [codex] Should state changes from keymap edits apply immediately or after explicit confirmation?
84. [codex] What transition feedback should appear when a user resets a mapping to default?
85. [codex] How should users perceive transition when an action becomes unavailable due to context change?
86. [codex] Should temporary disablement be represented as a separate state from unassigned?
87. [codex] How should the product handle transition when imported/shared keymaps conflict with personal preferences?
88. [codex] What signals should indicate a pending unsaved keymap state versus committed state, if applicable?
89. [codex] How should error states during key-triggered actions differ from configuration states?
90. [codex] What transition model best supports experimentation while minimizing accidental permanent changes?

## P2 (91-120)
91. [codex] Which user actions are considered core review actions versus convenience actions?
92. [codex] What does “configure mapping for each function” mean in user terms: remap, disable, or both?
93. [codex] Are all functions expected to be equally discoverable, or are some intentionally advanced?
94. [codex] Should keymaps represent user intent categories (commenting, triage, navigation) rather than raw command list items?
95. [codex] What is the expected relationship between commands and keymaps in the user mental model?
96. [codex] How much consistency with common Neovim review workflows is expected by target users?
97. [codex] Are users expected to use the plugin primarily in short sessions or sustained review sessions?
98. [codex] Do users view mapping choice as personal preference or team-level convention in shared configs?
99. [codex] Should the domain treat “line comment” and “range comment” as separate first-class actions for mapping semantics?
100. [codex] Is “next unreviewed file” conceptually navigation, review state management, or both?
101. [codex] Which established Neovim plugins do users expect this plugin’s keymap behavior to resemble?
102. [codex] How do comparable code-review tools expose configurable shortcuts by action category?
103. [codex] Do users expect mapping disable behavior to match common Neovim plugin conventions?
104. [codex] What default key choices are already culturally overloaded in review-focused setups?
105. [codex] How do similar tools communicate keymap discoverability in docs or help text?
106. [codex] Are there prior examples where per-function mapping flexibility increased usage in similar plugins?
107. [codex] How do comparable tools handle mode-specific expectations for selection-driven actions?
108. [codex] What are common user complaints in prior art when shortcut customization is too rigid?
109. [codex] How do similar review workflows balance command discoverability versus shortcut density?
110. [codex] In prior tools, which actions are typically left unmapped by default and why?
111. [codex] What user pain is most severe today: missing mappings, poor defaults, or inability to disable conflicts?
112. [codex] How often do users need to customize mappings across machines or environments?
113. [codex] Are mapping conflicts currently causing users to avoid certain plugin functions entirely?
114. [codex] Which functions are currently underused due to discoverability versus shortcut friction?
115. [codex] Does lack of per-function configurability block adoption in teams with strict keybinding standards?
116. [codex] How critical is preserving existing user muscle memory during scope expansion?
117. [codex] What is the expected tolerance for changing defaults if configurability improves?
118. [codex] Are users asking for new mappings mainly to speed review flow or to reduce cognitive load?
119. [codex] Is the current issue mainly an expert-user limitation or a broad-user experience gap?
120. [codex] What proportion of daily review tasks depend on actions not currently easy to map?

## P3 (121-140)
121. [codex] What should user expectation be when a mapping is intentionally left unset for a function?
122. [codex] How should users reason about actions that are rarely used but still safety-critical (e.g., delete)?
123. [codex] If two preferred mappings collide in user config philosophy, which action should users prioritize?
124. [codex] Should temporary workflows (one-off reviews) and habitual workflows (daily reviews) be supported equally?
125. [codex] How should mapping expectations differ for users who rely heavily on visual selection behavior?
126. [codex] What happens to user expectations when optional plugin features are unavailable in their environment?
127. [codex] Should safety around destructive actions depend on having a shortcut, a command, or both?
128. [codex] How should users think about navigation mappings when no relevant target exists (e.g., no unreviewed files)?
129. [codex] Are there workflows where users intentionally avoid defaults and expect zero prebound actions?
130. [codex] Should accessibility-focused users be considered a primary audience for remapping flexibility?
131. [codex] What user-observable outcome proves per-function mapping scope is complete?
132. [codex] What minimum set of functions must be configurable to claim feature success?
133. [codex] How should success account for users who only disable mappings rather than remap them?
134. [codex] What indicates that configurability improved workflow speed in practice?
135. [codex] What indicates that configurability reduced keybinding conflict complaints?
136. [codex] What evidence would show improved adoption of previously underused functions?
137. [codex] How should backward compatibility be measured for existing user configurations?
138. [codex] What documentation-level outcome is required for users to self-serve mapping customization?
139. [codex] What qualifies as acceptable learning curve for first-time users of configurable keymaps?
140. [codex] What long-term maintenance signal would indicate the scope was well-bounded?
