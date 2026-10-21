# Writing reviews

## Choose independently reviewable topics

For a request to review or compare changes and put them in the inbox, publish
one thread per independently reviewable topic. This applies to intentional
changes, equivalent refactors, questions and observations as well as bugs.
"No regressions found" does not turn several differences into one topic.

Before writing, identify the topics from the requested scope. Separate changes
when a person could accept, question or respond to one without answering the
others. Keep an implementation change and its supporting tests together when
they explain the same topic. Do not make one item per file or manufacture bugs
or decisions to justify separate threads. Respect an explicit request for a
single summary.

Each topic needs its own explanation and relevant evidence. Shared branch
baselines, exclusions and validation can live in a short overview that links
to the topic threads. The overview supplements those items; a numbered report
with one diff does not replace them. For stacked branches, distinguish the
branch's own changes from differences inherited from its parent. Do not publish
inherited differences as newly introduced review topics.

Publish new topics together using publish with a durable request_id and a
unique key for each topic. Include the summary, source, comparisons and primary
choice in that call. Keep the manifest unchanged for recovery after a lost
response. Existing topics still use reply, finish, attach or revise as appropriate.

Before reporting completion, match the identified topic keys and intended
evidence to the complete publication receipt. A successful receipt confirms
the atomic save; do not read back full threads just to repeat that check.
After a lost response, recover the receipt with publications.read. If inspecting
existing state for another reason, project only the relevant fields.
If a topic could not be saved, report that gap instead of calling the whole
review complete.

## Explain the topic

Write each topic so a person can understand the change and respond without
reconstructing your investigation. Start with a short title naming the behavior
or consequence. For a bug, put the trigger and consequence first. For an
intentional change, explain what moved or changed and its practical effect.
Do not require a failure, severity or blocking recommendation for a sound
refactor. Explain the current outcome and any decision needed. Use internal function names
and test details where they help verify that explanation.

Recommend an action before asking for a decision. For an unresolved bug, propose
the fix or follow-up you would take and say whether you recommend blocking the
change. Ask the reviewer to accept or change that recommendation. Do not ask
them to design a solution, locate the responsible component or coordinate the
work you can investigate. For a fixed bug, identify the change to inspect and
the evidence supporting it. Keep parser and fixture inventories in supporting
evidence unless they are essential to understanding the consequence.

Keep one independently answerable concern in each thread. If a fix removes the
original bug but reveals a separate concern, explain the fixed outcome in the
original thread and create a linked finding for the remaining concern when it
needs its own decision. Do not split inseparable parts of one bug merely to fit
a template. Conversation resolution and whether code is fixed are independent.

## Evidence that explains the finding

Choose one primary example or comparison that makes the problem or change
obvious. A few lines of generated output can explain a documentation regression
better than a large parser diff. Compare versions of the same material and name
the baselines plainly, such as PR output versus locally fixed output. Do not
compare unrelated functions or an explanatory placeholder against real code.
Label hypothetical examples as illustrative rather than observed output.
Prefer captured output or a real code diff as the primary evidence when it is
available. An illustrative example can explain a claim but cannot verify the
fix. When evidence is unavailable, state that limit briefly and avoid asking
the reviewer to approve an implementation they cannot inspect. Do not create
constructed diffs simply to fill an attachment slot. A plain explanation may
be enough for an open question.

Use comparison for before/after text and attach for a navigable implementation
location. Tests can be supporting evidence, but do not substitute a test location
for the implementation being reviewed. Add extra comparisons only when they
answer a distinct verification question. Avoid copying commit IDs, worktree
paths, validation logs and an entire review report into every message.
Name a related finding by its readable title before its thread ID. Do not make
the reader interpret a bare ID to understand the relationship.

For new topics, publish selects primary_comparison using its item-local key.
For existing topics, use the discovered revise tool to set the current review title and summary and
select primary_comparison after saving the chosen comparison. Read the current
review id and pass expected_review when revising an existing summary. The
current summary is shown before discussion, while the original capture and
conversation remain available. Do not copy the same summary into a reply too.
Save discussion replies for new answers or decisions.

When correcting your own misleading comparison, use comparison_id to replace
it at its existing ID. The backend retains the prior version. Do not append a
second correction and leave the misleading evidence as the primary comparison.
If a comparison cannot be corrected with available evidence, withdraw it with
archiveComparison. It leaves the active source view and remains in history.
Discover current tool inputs before writing. These operations do not complete
a delivery claim, resolve a conversation or authorize editing someone else's
review. Refresh affected code attachments after code changes as the app skill
describes.

## Example

Title: Documentation references appear as literal markup

Summary: The PR wraps documentation references in backticks. The parser treats
them as code, so generated documentation displays the markup instead of the
property name. The local fix removes those backticks and references now resolve.
Please review the attached change.

Primary comparison, PR emission versus locally fixed emission:

````diff
- `{{% ref ... %}}`
+ {{% ref ... %}}
````

This is an illustrative emission example. Actual generated SDK output and the
implementation change can be supporting evidence. If resolved names still lose
code formatting, discuss that separately when it needs an independent decision.
