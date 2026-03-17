# JARVIS Brain – Test Case Scenarios

Manual test scenarios for the JARVIS brain features: documents, instructor focus, chat, quiz generation, examiner intentions, and study recommendations.

---

## Prerequisites

- **Gemini API key** (free): https://aistudio.google.com/apikey  
- At least **one subject** in the app (e.g. "Physics", "Math").  
- Optional: a few **tasks** and **study topics** for richer context.

---

## 1. API Key (Gemini)

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 1.1 | Set API key first time | 1. Open app → Campus tab → tap JARVIS FAB.<br>2. Tap **key icon** (top right).<br>3. Paste a valid Gemini API key → **Save**. | Dialog closes. No error. |
| 1.2 | Chat without key | 1. Clear key (e.g. set to empty and Save) or use a fresh install with no key.<br>2. Open JARVIS → type "Hello" → Send. | Reply says to set API key and points to aistudio.google.com/apikey. |
| 1.3 | Chat with valid key | 1. Set valid key (1.1).<br>2. Type "What subjects do I have?" → Send. | JARVIS replies using your actual subject names from the app. |

---

## 2. Instructor Focus (per subject)

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 2.1 | Save instructor focus | 1. Subjects → open a subject (e.g. Physics).<br>2. **JARVIS** tab.<br>3. In "Instructor focus", type: "Problem-solving and past exam style".<br>4. Tap **Save instructor focus**. | Snackbar: "Saved. JARVIS will use this." |
| 2.2 | Focus used in chat | 1. After 2.1, open JARVIS (Campus → JARVIS).<br>2. Ask: "What should I focus on for Physics?" | Reply mentions problem-solving / past exam style (or similar) based on what you saved. |
| 2.3 | Change focus | 1. Same subject → JARVIS tab.<br>2. Change text to "Definitions and formulas".<br>3. Save. | New text is stored. Next time you ask about focus for that subject, JARVIS uses the new text. |

---

## 3. Documents & Past Exams (per subject)

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 3.1 | Add document (paste) | 1. Subject → JARVIS tab.<br>2. **Add document**.<br>3. Name: "Ch.3 notes".<br>4. Paste 2–3 paragraphs of text (e.g. lecture notes).<br>5. **Save**. | Document appears in list with name and type "document". |
| 3.2 | Add past exam (paste) | 1. Same subject → **Past exam**.<br>2. Name: "Midterm 2024".<br>3. Paste exam questions (or sample Q&A).<br>4. **Save**. | Document appears with type "past_exam". |
| 3.3 | Add from file (.txt/.md) | 1. **Add document**.<br>2. Before filling form: pick a .txt or .md file (if the file picker runs).<br>3. Enter name, then **Save**. | Content from file appears in the content field; after Save, document is stored. |
| 3.4 | Delete document | 1. In JARVIS tab, tap **delete (trash)** on one document. | Document disappears from list. |
| 3.5 | Validation | 1. **Add document** → leave Name empty → Save. | Snackbar: "Enter a name". |
| 3.6 | Validation | 1. **Add document** → enter Name only, leave content empty → Save. | Snackbar: "Paste or add some content". |

---

## 4. JARVIS Chat (brain with full context)

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 4.1 | Chat uses subjects | 1. Ensure you have subjects (e.g. Physics, Math).<br>2. JARVIS → type: "List my subjects." | Reply lists your actual subject names. |
| 4.2 | Chat uses tasks | 1. Add a task with due date (e.g. "Physics homework" due tomorrow).<br>2. JARVIS: "What tasks are due soon?" | Reply mentions the task and timing. |
| 4.3 | Chat uses documents | 1. Add a document for Physics with text like "Ohm's law: V = IR".<br>2. JARVIS: "What does my Physics Ch.3 document say about Ohm's law?" (or "Summarize my Physics notes.") | Reply refers to V = IR or your document content. |
| 4.4 | Multi-turn | 1. Ask: "How many subjects do I have?"<br>2. Then: "Which one has the most tasks?" | Second reply is consistent with your data (subject with most tasks). |
| 4.5 | Voice → brain | 1. Hold **mic** in JARVIS, say "What should I study today?"<br>2. Release. | Transcription is sent to the brain; JARVIS replies (text + TTS) using your context. |

---

## 5. Quick Action: Recommend study times

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 5.1 | Get recommendations | 1. JARVIS → tap chip **Recommend study times**. | A message is sent to the brain; reply suggests what to study and when (today/tomorrow), referring to timetable, due tasks, or topic reviews. |
| 5.2 | With empty data | 1. New profile: no tasks, no timetable.<br>2. Tap **Recommend study times**. | Reply is generic but no crash (e.g. "Add tasks or topics to get tailored recommendations."). |

---

## 6. Quick Action: What to focus on?

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 6.1 | Per subject | 1. JARVIS → **What to focus on?**<br>2. Choose a subject (e.g. Physics). | Reply covers examiner intentions, what to focus on, and topic weight % (if you added past exams/documents for that subject). |
| 6.2 | All / general | 1. **What to focus on?** → choose "All / general". | Reply gives general advice across subjects. |
| 6.3 | With instructor focus + past exam | 1. Set instructor focus for Physics (2.1).<br>2. Add a past exam for Physics (3.2).<br>3. **What to focus on?** → Physics. | Reply aligns with instructor focus and content of the past exam (intentions, weights). |

---

## 7. Quick Action: Test me (quiz)

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 7.1 | Generate quiz (with materials) | 1. Add at least one document or past exam for a subject.<br>2. JARVIS → **Test me** → select that subject. | After a short load, **Quiz** screen opens with 5 questions (MCQ and/or short answer). |
| 7.2 | Generate quiz (no materials) | 1. **Test me** → select a subject that has **no** documents or past exams. | Either a short quiz from general context or a message like "Could not generate quiz. Add past exams or documents...". No crash. |
| 7.3 | Answer MCQs | 1. On quiz screen, tap one option per MCQ. | Selected option is highlighted (e.g. purple); only one option selected per question. |
| 7.4 | Answer short answer | 1. On a short-answer question, type in the text field. | Text is stored as your answer. |
| 7.5 | Submit and get feedback | 1. Answer all questions (or leave some blank).<br>2. Tap **Submit & get feedback**. | Button shows "Grading..."; then **JARVIS feedback** screen with a paragraph + bullet feedback (right/wrong, correct answer, explanation). |
| 7.6 | Back to JARVIS | 1. On feedback screen, tap **Back to JARVIS**. | Returns to JARVIS overlay. |

---

## 8. Quiz screen edge cases

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 8.1 | No questions in payload | (Would require broken API response.) If quiz has 0 questions, screen shows empty list + Submit. | No crash; Submit may still call grading (empty list). |
| 8.2 | Mixed MCQ + short | 1. Generate quiz for a subject with enough content.<br>2. Ensure at least one MCQ and one short-answer question. | Both types render: MCQ with options and tap-to-select; short answer with text field. |
| 8.3 | Submit only MCQs | 1. Answer only MCQs; leave short-answer blank.<br>2. Submit. | Grading runs; feedback mentions the short-answer (e.g. "You left X blank" or similar). |

---

## 9. Integration / data flow

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 9.1 | New document affects chat | 1. Add a new document for a subject.<br>2. Without restarting, open JARVIS and ask about that subject or that document. | Reply uses the newly added content. |
| 9.2 | New instructor focus affects focus query | 1. Set instructor focus for a subject.<br>2. **What to focus on?** → that subject. | Reply reflects the instructor focus. |
| 9.3 | Delete subject | 1. Delete a subject that has JARVIS documents and instructor focus. | Subject is removed; associated documents and metadata are removed (no orphan rows; no crash when opening JARVIS). |

---

## 10. UI / UX checks

| # | Scenario | Steps | Expected result |
|---|----------|--------|------------------|
| 10.1 | JARVIS tab in subject | 1. Subject detail → tabs. | Sixth tab **JARVIS** with psychology icon is visible and opens the JARVIS tab (instructor focus + documents list + Add document / Past exam). |
| 10.2 | Quick chips | 1. Open JARVIS overlay. | Three chips visible: "Recommend study times", "What to focus on?", "Test me". Tapping each triggers the correct action. |
| 10.3 | Input row | 1. JARVIS overlay. | Text field "Ask JARVIS anything...", Send button, and mic button visible. Send submits typed text; mic starts/stops recording. |
| 10.4 | Loading state | 1. Send a message or tap **Test me** (with slow network if possible). | Loading indicator or "..." / "Grading..." where appropriate; no double submissions. |

---

## Summary checklist

- [ ] **1** API key: set, missing, valid
- [ ] **2** Instructor focus: save, used in chat, change
- [ ] **3** Documents: add (paste + file), delete, validation
- [ ] **4** Chat: subjects, tasks, documents, multi-turn, voice
- [ ] **5** Recommend study times
- [ ] **6** What to focus on? (per subject, all, with focus + past exam)
- [ ] **7** Test me: generate quiz, answer MCQ/short, submit, feedback, back
- [ ] **8** Quiz edge cases: no questions, mixed types, partial answers
- [ ] **9** Integration: new doc/focus used immediately; delete subject
- [ ] **10** UI: JARVIS tab, chips, input row, loading

Use this file to run manual tests after changes to the JARVIS brain, documents, instructor focus, or quiz flow.
