---
title: Structured Consent
---

## Before You Begin

This **unsigned example** demonstrates Markdown and interactive fields. It is not an active research study.

### Your Choices

1. Read the information.

   Take as much time as you need.

2. Ask questions before deciding.

> You may stop participating at any time.

### Collection Summary

| Measurement | Frequency |
| --- | --- |
| Heart rate | When available |
| Study check-in | Once a week |

### Contact the Team

[Email the research team](mailto:study@example.com) with questions.

`Consent is not a condition of receiving care.`

<toggle id=agree initial-value=true expected-value=true>
I have read the **study information**.
<footnote>Please ask about anything that is unclear.</footnote>
</toggle>

<select id=contact initial-value=email>
Preferred contact method.
<option id=email>Email</option>
<option id=phone>Phone</option>
</select>

<signature id=participant />
