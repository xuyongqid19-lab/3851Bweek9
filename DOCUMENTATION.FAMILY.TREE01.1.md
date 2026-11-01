# Family Tree — Product and Implementation Plan

Version 1.2 · 15 October 2026 · FAM07–FAM12 implemented, including the expanded visual tree and illustrated English user guide. Evidence and inherited baseline issues: [implementation review](DOCUMENTATION.FAMILY.TREE01.REVIEW.md).

This specification extends the existing Family plan with FAM07–FAM12. It is based on the user's 15 October request and the Family implementation in `GlobalVillage-Team-Merged-Final(2).zip`. The October team package is the integration baseline. Existing authentication, chat, community, profile and recommendation behavior must be preserved. Assignment-facing text and new application copy are English.

## 1. Purpose and terminology — FAM07

Connect separate family groups into a shared **Family tree**, while retaining each group's own members, administrators and private records. A node represents a family group, not a person. A confirmed connection represents a relationship agreed by the participating administrators. A connected set of nodes is one tree; there is no separate super-administrator who can control all groups.

The first version is a **group-based family tree**, not a verified genealogical register. Existing labels such as Dad or Uncle describe a person's role inside one group; they must never be used to infer ancestry, generations, identity across groups or automatic connections. Tree depth is distance from the selected viewing group, not age or seniority. Example: Chen Home — Grandparents Home — Aunt's Home.

A group can have several direct connections but belongs to only one connected tree at a time. A user may belong to groups in several separate trees. Changing the user's primary family does not change the tree or anyone's permissions. No family group is created automatically by linking.

## 2. Navigation and screen contents

Keep the existing Family bottom-navigation item and its primary-family summaries and other-family message list. Add a **Family tree** card below the primary-family panel, showing the primary group's connected-family count and requests awaiting this user's administrative review. Add the same entry to each family's settings. Do not add another global bottom-navigation item.

`Family → Family tree → choose one of my family groups → Tree / Requests / Manage`.

The selected group is always visible. Switching groups reloads its authorized view and clears any previous group's form or error state. Opening a tree never changes the user's primary family.

| Screen | Contents and actions |
| --- | --- |
| Tree | Group nodes, confirmed relationship labels, connection paths, selected-group highlight, a text explanation that layout is not ancestry, refresh. A responsive connected outline remains readable on narrow screens and with large text. |
| Group node | Shared group name and relationship. If the user actually belongs to the group, Open family navigates to its existing details. Otherwise show a limited connected-group card; do not expose membership invites or private details. |
| Requests | Pending requests and the latest 100 resolved requests for the selected group; endpoint names, relationship, optional explanation, expiry, approval progress, status/reason and permitted actions. Pending work remains visible even if there are more than 100 old requests. |
| Manage | Administrators can copy/reset their group's separate connection code, preview a destination, send a request, or disconnect their group's direct connections. The owner can leave all connections after reviewing the consequences. Ordinary members see explanatory read-only text. |

No-family state keeps Create family and Join family as the first steps. A family with no connections shows its own node, “No connected families yet”, and an administrator action to connect. Ordinary members are told to contact an administrator. Network or authorization errors show a retry/sign-in explanation, not an empty tree or a false success.

### 2.1 Large visual tree — FAM07 extension

The Tree tab offers **Open large tree**. It opens a full-screen canvas with one card per group and visible lines for every confirmed connection. Arrange branches by connection distance from the selected group, never by inferred ancestry. Highlight the selected group with text as well as colour. Show agreed labels on the connected cards; tapping any card opens its full name, direct relationships and membership access explanation.

Users can drag the canvas, pinch or use **Zoom in**, **Zoom out**, **Show all** and **100%** controls. Show all fits every node and line, including a 50-group tree. At that scale small text may require zooming. The existing outline remains available through Back for large-text and screen-reader use. Controls wrap on narrow screens and have readable labels and touch targets. Empty trees still display their own group. Refresh retrieves the authorized current tree and resets the view; a failed or revoked refresh hides old topology with a retry message. Opening private family details remains subject to existing membership checks.

Acceptance: verify a branched tree, a long chain, 50 groups, long names and labels, mobile width, enlarged text, zoom/pan/fit, node details, refresh failure and navigation back to the outline. Deliver an English PowerPoint guide for older users, with one short action and an actual app screenshot per step. Cover both administrator roles, unanimous approvals when extending a tree, the large canvas and safe disconnection. Screenshots use synthetic local demonstration accounts only.

## 3. Adding groups and making connections — FAM08

### 3.1 Create or join a family

Reuse the existing Create family and Join family forms, including required real name and per-family relationship. The new family starts as one independent node. Existing membership invite codes retain their original purpose. Joining a tree never enrolls a person into another family, grants an administrator role, or copies records.

### 3.2 Separate connection code

Each group has a random **tree connection code**, visible only to its current owner/administrators. It is separate from the membership invite code. The target administrator shares it with the requesting administrator outside the app. There is no public family directory or name-based search. Possessing the code only allows a limited preview and a request; it grants no membership or automatic approval.

Preview exposes the target group name and the number of affected groups only. Resetting a connection code invalidates its old value and pending requests created with that value; it does not remove confirmed connections or change membership invitations.

### 3.3 Request form and preview

1. Select a family that the current user administers.
2. Enter the destination's tree connection code and preview the destination.
3. Choose a neutral relationship label (Related households, Maternal branch, Paternal branch, Extended family, or a custom label up to 80 characters). This is agreed descriptive text, not an automatically calculated blood relationship.
4. Optionally explain the connection in up to 500 characters. Do not request ID numbers, addresses or health information.
5. Review the two endpoint names, how many groups will become connected, and the visibility/consent notice. Explicitly confirm before submitting.
6. Submit once. The source group's current administrator records the source group's consent. Other affected groups see the request in their administrators' request lists. No external messages or push notifications are sent.

Changing the code after preview clears the preview. The server repeats all checks on submission. Self-links, an existing connected path, duplicate pending requests in either direction, invalid codes and a combined tree above 50 groups are rejected. Each affected group may participate in at most 20 pending requests; preview/send attempts are rate limited per authenticated user.

### 3.4 Approval and merging whole trees

Two isolated groups require both groups' approval: submission counts for the source; a current target administrator accepts or rejects. Approval by any one current owner/administrator represents that group. The same person may administer both groups and deliberately act for both, consistent with existing multi-family support.

When adding a third group or linking two existing trees, **every affected group's current administrator must consent**. Connecting two nodes also reveals the combined topology to existing members, so consent from only the two endpoint groups is insufficient. Submission records one group vote; all other groups in the two components receive the proposal. Show “2 of 3 families approved”, not a false “Connected” state before final acceptance. Previously approved groups do not need to vote again unless the proposal becomes invalid.

Any required group can reject the entire proposal. A current source-group administrator can cancel it. An administrator whose group has already approved can still reject while the request is pending. Ordinary members cannot read administrative proposals or vote. The first valid final decision wins; later contradictory actions receive a conflict and refresh the view.

Requests expire after seven days, using server UTC time. The server stores a snapshot of both components and their connections. Before listing, voting or finalizing it rechecks expiry, code validity, existing groups, all consent-givers' current administrative roles, and the topology snapshot. Any change invalidates the proposal with a clear reason; the user must send a new proposal. A family rename uses the current name in current views and does not create a new group identity.

Final acceptance atomically saves the connection, resolves the request and emits generic Family update entries to affected groups. Simultaneous accept/merge operations cannot create duplicate edges, cycles or bypass later consent. Retrying an already completed identical action is safe; an incompatible replay is rejected. The displayed tree is rebuilt from confirmed connections only.

### 3.5 Request states

| State | Meaning | Next action |
| --- | --- | --- |
| Pending | Some required family approvals are missing | Approve, reject, cancel or wait |
| Accepted | All required approvals were valid and the connection was saved | View tree; use Disconnect for later withdrawal |
| Rejected | One required family declined | Read reason; send a new request if appropriate |
| Cancelled | Source administrator withdrew it | Start a new request if needed |
| Expired | Seven days elapsed without completion | Send a new request |
| Invalidated | Code, authority or topology changed; a group closed | Refresh and create a new proposal |

Resolved requests cannot be edited or revived. Proposed labels cannot be changed after submission; cancel and resubmit so all administrators approve the same statement.

## 4. Permissions and privacy — FAM09

| Capability | Family member | Family administrator | Family owner |
| --- | --- | --- | --- |
| View confirmed tree containing one of their current groups | Yes | Yes | Yes |
| Read another group's members, health notes, tasks or activity details merely because of tree connection | No | No | No |
| Obtain membership access to another group | Existing join flow only | Existing join flow only | Existing join flow only |
| Manage connection code, submit and decide requests for their own group | No | Yes | Yes |
| Disconnect an edge incident to their own group | No | Yes | Yes |
| Disconnect an edge between two other groups | No | No | No |
| Leave all tree connections for their group | No | No | Yes |
| Change another group's roles/settings | No | No | No |

Shared topology contains group IDs, group names and confirmed relationship labels only. No member names/counts, emails, invites, health notes, activity/task payloads or administrator identities are included. Request explanations are visible only to administrators of participating groups. Before linking, prospective reviewers receive the endpoint names and aggregate approval counts; they do not receive the other tree's complete node list or members.

All API requests use the existing Auth bearer token and current server-side membership checks. Client-supplied user IDs and hidden UI buttons are not authorization. A person who leaves their last group in a tree loses that tree's access immediately; if they still belong to another connected group they retain access through that group only. No offline private-tree cache is introduced.

## 5. Disconnection, leaving and group lifecycle — FAM10

**Disconnect one relationship:** either endpoint's current administrator may withdraw the relationship without requiring the other group to agree. Show the endpoint names and the resulting component sizes before confirmation. Only that edge is removed; existing families, memberships, accounts and records survive. In a tree, removing an edge splits it into two independent trees. Nodes are not silently reparented and no new relationship is invented.

**Leave tree:** a current group owner may remove all links incident to that group. Show the number of direct links and explain that the former tree may split into several branches. The group remains usable on its own, and all other groups remain intact. Rejoining later requires a new request. Reject this bulk action for ordinary administrators; they retain the explicitly confirmed per-link withdrawal action.

**Close an empty group:** preserve the existing final-member leave flow, with an additional warning that the group's connections will disappear and branches may split. Deleting the group cascades its connection/code records, invalidates pending proposals and generates generic updates for surviving affected groups. Never delete another family or its contents.

**Change administrators:** confirmed connections remain after an owner transfer or role change. A pending vote becomes invalid when its consenting account is no longer an administrator of that group. A newly appointed administrator may decide outstanding valid proposals; old credentials never preserve old privileges.

**Edit a relationship:** do not silently edit an agreed label. Disconnect and submit a new proposal. A future amendment workflow can reuse unanimous approval, but is not part of this release.

## 6. Persistence and API — FAM11

Extend the existing Family SQLite service with additive tables. Keep Auth, Community and Chat PostgreSQL schemas unchanged. Existing Family data must open without reset or importing sample families.

| Storage | Responsibility |
| --- | --- |
| Tree connection codes | One code per family; unique random value; cascade on family closure |
| Confirmed connections | Stable ID, two distinct group IDs, approved label, creation time; unique undirected pair; foreign keys cascade |
| Connection requests | Endpoint IDs and display snapshots, proposal, creator, created/expiry/resolution time, status/reason, destination code snapshot, component fingerprint, required group IDs and recorded votes |

Connected components are derived from confirmed edges rather than stored as competing group membership lists. There is no second family identity system. All accepted links form an acyclic forest with at most 50 groups per component. Transactions serialize final approval and disconnection; a failed write rolls back connection, status and events together. Keep resolved request history (latest 100 in the UI) without storing unnecessary personal information.

Suggested existing-service routes, all authenticated and scoped to the selected group:

- `GET /families/:groupId/tree` — confirmed topology, own role, allowed actions, admin-only requests/code.
- `POST /families/:groupId/tree/preview` — limited code preview and consent counts.
- `POST /families/:groupId/tree/requests` — propose a connection.
- `POST /families/:groupId/tree/requests/:requestId` — approve, reject or cancel with a decision field.
- `POST /families/:groupId/tree/code` — reset the connection code.
- `POST /families/:groupId/tree/disconnect/:connectionId` — withdraw an incident edge.
- `POST /families/:groupId/tree/leave` — owner withdraws all group connections.

The tree module owns topology and proposal authorization. Existing FamilyStore owns group memberships and records. Existing FamilyService transports authenticated HTTP. A dedicated Flutter tree page owns display and forms; main Family navigation only opens it. Keep group and tree authorization in the server, not in client calculations.

## 7. Failure handling and consistency

Disable the active form's submit/decision controls while a request is running. Preserve user-entered code, label and explanation on a failed request. On a timeout after submission, refresh request history before offering another send; a duplicate pending proposal must not be created. A success banner appears only after the server confirms the saved result.

Use loading, empty, retry, expired-session, permission-revoked and conflict states explicitly. On group-switch or route disposal, ignore stale responses. Refresh after each action and on explicit refresh; the first release does not claim live push or background synchronization. A stale client must not approve a changed topology or remove an unrelated connection. Confirmation text is derived from the latest server snapshot; if the snapshot changes, require refresh before proceeding with a destructive topology change.

## 8. Acceptance criteria — FAM12

1. October Auth, Chat, Community, Profile and recommendation files remain the baseline; document every necessary integration difference. Do not copy real environment secrets or databases from the archive.
2. Family homepage and group settings reach the correct tree without changing primary-family preference. No-family and ordinary-member states remain usable at mobile width and larger font sizes.
3. Administrator A previews B with the separate tree code; wrong codes and membership invite codes fail without exposing records.
4. A sends, B sees Pending and accepts; both groups' members see the same confirmed connection and label after refresh. Before acceptance no connection exists.
5. Linking C to A–B needs A, B and C consent. Linking A–B and C–D needs four group votes. One rejection prevents the entire merge.
6. Duplicate/reverse/self/same-component proposals, cycles, over-limit graphs and unauthorized actions are rejected server-side. A user administering both endpoints can complete the two explicit group actions.
7. Rejection, cancellation, expiry, code rotation, role revocation, group closure and topology changes produce correct terminal states. Repeated final approvals do not create duplicate connections or events.
8. A linked-tree member still cannot call another family's detail/notes/activity APIs; request internals and codes remain admin-only. An unrelated user cannot obtain topology by guessing IDs.
9. Removing a bridge produces the expected two components; bulk leave and family closure split branches without deleting unrelated records. Previous access is revoked on refresh/API calls.
10. Reopening an old SQLite database preserves all previous records and adds empty tree tables; reopening after accepted requests restores topology/history. Write failures roll back whole operations.
11. Exercise real authenticated HTTP and Flutter request/forms/navigation, then run relevant backend suites, all Flutter tests, analyze and a Web release build. Record pre-existing issues separately.
12. Deliver the planning document first. Then record implemented behavior, actual verification results and remaining platform limits in a concise implementation handoff; do not claim unrun Android, public-demo, SMTP or Google-login tests.

## 9. Implementation order and boundaries

1. Finish this specification, add FAM07–FAM12 to the Family plan and show it to the user before business-code edits.
2. Integrate the October team code in the local repository with a recoverable pre-integration checkpoint and a file comparison report. Preserve private local configuration and the existing portable tooling; assess compatibility without silently replacing teammate behavior.
3. Implement additive tree persistence, permission checks, unanimous proposal state machine, disconnection and HTTP routes; test security and rollback first.
4. Add English Flutter tree navigation, node view, request review and management forms; reuse existing authenticated services and group pages.
5. Verify the main user flows and teammate regressions, resolve attributable failures, update status and provide launch/inspection steps.

Not included: individual-person ancestry, automatic kinship inference, birth/death/ID records, cross-family private-record sharing, shared group chat, external invitations, push notifications, public publishing, moderation appeals, media uploads or ownership of an entire clan. Existing launch tools are retained; a newly rebuilt portable distributable is a separate packaging task unless needed to verify this implementation.
