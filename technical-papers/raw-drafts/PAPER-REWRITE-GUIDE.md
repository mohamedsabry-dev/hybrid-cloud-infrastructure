# Technical Paper Rewrite Guide — Internal Reference

Rules for trimming papers from encyclopedia format to trace format.
Based on the original 3 storage papers + the OIDC rewrite session.

---

## What a paper IS

A trace. Step-by-step signal flow from trigger to completion.
Each step = one handoff point that feeds into the next.
The paper answers: "walk me through what happens when..."

## What a paper is NOT

- An encyclopedia ("what is X", "how X works in general")
- A comparison table ("X vs Y side by side")
- A gap analysis ("known gaps", "future plans")
- A design doc ("why we chose X over Y")
- Interview Q&A ("what is the difference between PAM and PVE")

All of that is head knowledge — Sabry knows it from massive coverage
sessions and prep chunks. It lives in his mind for interview answers,
not in the paper.

---

## Rewrite method

1. Read the full paper
2. Identify every TRACE STEP — a point where signal moves from A to B
3. Identify every EXPLANATION BLOCK — "what is X", concept definitions,
   comparison tables, design rationale, gap lists
4. Keep ALL trace steps — do not drop any handoff
5. Cut ALL explanation blocks, UNLESS the explanation is embedded
   inside a trace step as 1-2 lines of essential context
6. If a concept is needed to understand a step, compress it to 1 line
   within the step (e.g. "API-only user, no OS access" instead of a
   10-line PAM vs PVE section)
7. One-time setup that must happen before the trace can run goes in a
   compressed "Pre-Trace" section (3-5 items, 2-3 lines each max)
8. No "Known Gaps" section — gaps are head knowledge
9. No comparison tables
10. No design rationale sections

## Step format

Follow the original papers:

    ### Step N — Short Label

        trigger or input
          |
          +-- what happens at this layer
          |     essential detail (1 line, not a paragraph)
          |
          +-- output handed to next step

## Summary trace format

After the full paper is done, create a summary in summary-traces/:
- Pure arrow chain (→) — no headers, no step numbers, no sections
- Every line is a handoff
- Reads as one continuous flow from start to finish
- Pre-trace setup compressed to 2-3 lines at top
- No explanations — just the signal path

## Comparison checklist

After rewrite, compare old vs new line-by-line:
- Extract every trace step from the old version
- Verify each one exists in the new version
- Report any dropped steps to Sabry before finalizing
- Explanation content that was cut does NOT count as dropped
