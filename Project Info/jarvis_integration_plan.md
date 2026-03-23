# JARVIS — Complete Integration Plan
*Based on full codebase audit. Awaiting your approval before implementation.*

---

## What Already Exists (Do Not Rebuild)

Before listing new features, here is what the app already does that we build ON TOP OF:

- `didChangeAppLifecycleState` in campus.dart → detects every app resume/pause
- `NotifService.schedule()` → can fire any notification at any future time, recurring or one-shot
- 7 notification channels already registered (study, exam, timetable, deep_study, read_my_day, urgent_tasks, reminder_notifs)
- `JarvisDocuments` table → stores full extracted text of every PDF you upload (lectures, sheets, past exams)
- `buildContext()` in brain service → already assembles all subject data into one string for AI
- `chat()` method → Gemini receives full context on every message
- Absence warning system → already fires when you hit max-1 absences
- Night Before Protocol → already triggers when exam is tomorrow
- TTS (flutter_tts) → already wired and speaking in campus.dart and jarvis_overlay.dart

Everything new below is additive. Nothing existing gets removed.

---

## THE PLAN — 5 Features

---

### FEATURE 1: JARVIS Auto-Launch System

**The idea:** JARVIS activates himself in specific situations without you doing anything. Not randomly. Only when something matters.

---

#### Trigger A — App Open Briefing (Every time you open the app)

**How it works technically:**
`didChangeAppLifecycleState` already exists in campus.dart. When `AppLifecycleState.resumed` fires, we check: has a briefing been given in the last 2 hours? If no → JARVIS speaks.

**What JARVIS says (TTS, 20-40 seconds):**
```
"Good morning, sir. Today you have 3 classes: 
 Electronics at 9, Digital Logic at 11, and a lab at 2.
 You have 2 absences in Electronics — one more and you're barred.
 Your Networks midterm is in 4 days. You have 7 overdue topics.
 Your plan for today is ready."
```

**Rules:**
- Only speaks once per 2-hour window (not every time you switch apps)
- Morning (6-11am): full brief including timetable + urgent tasks + overdue topics
- Afternoon (11am-6pm): short brief, only if an exam is within 48h or an absence is critical
- Evening (6pm+): only speaks if you have a task due tomorrow or an exam the next day
- Midnight to 6am: silent, no brief

**Requires:** No new packages. Uses existing TTS + `didChangeAppLifecycleState` + SharedPreferences to track last-spoken timestamp.

**Feasibility: 100% — pure Dart, no new dependencies.**

---

#### Trigger B — Scheduled Daily Check-ins (User-controlled times)

**How it works:**
In JARVIS settings, you set 1-3 times per day. Example: 7:00 AM, 2:00 PM, 10:00 PM. These get saved and scheduled as repeating notifications using existing `NotifService.schedule()`.

When the notification fires → you tap it → app opens → JARVIS immediately speaks the relevant brief for that time of day.

**Morning notification (7:00 AM):**
```
"JARVIS — Morning Brief Ready"
Body: "3 classes today. Electronics absence critical. Tap to hear full brief."
```

**Afternoon notification (2:00 PM):**
```
"JARVIS — Afternoon Check"
Body: "Networks midterm in 3 days. 7 topics overdue. Tap now."
```

**Night notification (10:00 PM):**
```
"JARVIS — Evening Report"
Body: "Tomorrow: 2 classes. Digital Logic quiz at 11. Tap to review plan."
```

**Settings UI:** A simple settings page where you toggle and set up to 3 daily JARVIS check-in times with a time picker for each.

**Feasibility: 100% — uses existing schedule() method, just adds a settings page.**

---

#### Trigger C — App Usage Watchdog (Android Only)

**The idea:** You've been on Instagram for 45 minutes. JARVIS fires a notification: *"45 minutes on Instagram. You have 7 overdue topics and an exam in 3 days. I suggest you reconsider."*

**How it works technically:**
Android has `UsageStatsManager` — it logs how long you use every app. Flutter package: `app_usage`. You set a threshold per social app (e.g., 30 minutes). A background check runs every 15 minutes using `WorkManager` (Flutter: `workmanager` package). If threshold crossed → fires notification.

**CRITICAL HONESTY:**
- Android only. iOS does not allow this at all (Apple locks Screen Time data).
- Requires the user to manually go to: Settings → Apps → Special App Access → Usage Access → and enable it for this app. Cannot be granted automatically. If user doesn't grant it, this feature simply stays disabled.
- Background service can be killed by aggressive battery savers (Xiaomi, Huawei especially). Workaround: instruct user to disable battery optimization for the app.

**This is the only feature in the entire plan with uncertain reliability.** Everything else is guaranteed to work.

**If you want this:** We add it as an optional module in settings. User grants the permission manually. We add 2 new packages to pubspec: `app_usage` and `workmanager`. ~150 lines of new code.

**If you don't want this:** Skip it. The other 4 features are stronger and more reliable.

**Feasibility: 80% on Android, 0% on iOS.**

---

### FEATURE 2: Study Schedule Builder

**The idea:** You tell JARVIS when you're free. He looks at your timetable. He knows your subjects, marks, PDFs, overdue topics, and exam dates. He builds you a precise, hour-by-hour study plan for the entire week — specific subject, specific topic, specific duration, specific reason. You can regenerate it any time.

---

**Step 1 — You enter your fixed available time:**

A "My Week" settings screen. You fill in once and save:

```
Monday:    Free from 4:00 PM to 8:00 PM
Tuesday:   Free from 3:00 PM to 7:00 PM  
Wednesday: Free from 5:00 PM to 9:00 PM
Thursday:  No free time
Friday:    Free all day (9:00 AM to 9:00 PM)
Saturday:  Free from 2:00 PM to 8:00 PM
Sunday:    No free time

Preferred session length: 45 minutes
Break between sessions: 15 minutes
```

**Step 2 — JARVIS computes the real free windows:**

JARVIS takes your "I'm free from 4-8pm Monday" and subtracts any classes in the timetable that fall in that window. What remains is actual study time.

Example:
```
Monday "free" 4:00 PM - 8:00 PM
  → Timetable shows: Lab at 4:00-6:00 PM
  → Actual study time: 6:00 PM - 8:00 PM = 2 hours
  → With 45-min sessions + 15-min breaks: 2 sessions
```

**Step 3 — JARVIS prioritizes subjects for each slot:**

Using this algorithm (no AI needed, pure logic):
1. Subjects with an exam within 7 days → highest priority
2. Subjects where mark average is declining → second priority
3. Subjects with the most overdue spaced repetition topics → third priority
4. Subjects with low topic mastery (many stage-0 or stage-1 topics) → fourth priority
5. Remaining subjects → rotated evenly

**Step 4 — AI generates the detailed plan:**

Gemini receives: your weekly free windows + timetable + all subject data (marks, topics, past exam patterns, instructor focus) and generates:

```
═══════════════════════════════════════════════════
JARVIS WEEKLY STUDY PLAN — Week of Nov 18-24
Generated: Sunday 10:23 PM
═══════════════════════════════════════════════════

MONDAY — 2 sessions available (6:00 PM - 8:00 PM)

  ▸ 18:00 – 18:45 | Electronics | Transfer Functions
    Why: Exam in 5 days. This topic appeared in 3 of 5 past midterms.
    Your Stage: 1 (Seen Once) — needs 2 more reviews minimum.
    Focus: Practice deriving H(s) from circuit diagrams. Past exams ask
    this in 40% of Q1 problems.
    
  ⏸ 18:45 – 19:00 | Break

  ▸ 19:00 – 19:45 | Digital Logic | K-map Minimization (4-variable)
    Why: Stage 0 — never reviewed. Foundational for next topic (SOP/POS).
    Dr. Hassan repeats K-map questions every midterm without exception.
    Focus: Complete at least 3 practice K-maps from Sheet 3.

TUESDAY — 3 sessions available (3:00 PM - 7:00 PM)

  ▸ 15:00 – 15:45 | Networks | OSI Model Layers
    Why: 2 overdue topics in Networks. This is the prerequisite for 
    TCP/IP which you have not touched. Cannot skip.
    Focus: Memorize layer functions + real-world protocols per layer.
    
  ⏸ 15:45 – 16:00 | Break

  ▸ 16:00 – 16:45 | Electronics | Operational Amplifiers
    Why: Your last Electronics quiz score was 62% (below your 75% average).
    Op-Amp appeared in both previous finals. Dr. Samir marks partial credit
    for correct circuit drawing even if calculation is wrong.
    
  ⏸ 16:45 – 17:00 | Break

  ▸ 17:00 – 17:45 | Mathematics | Laplace Transforms
    Why: No sessions scheduled yet this week. Exam in 14 days — 
    enough time to master if you start now. Do not delay.

[...continues for all days...]

═══════════════════════════════════════════════════
THIS WEEK'S NON-NEGOTIABLES:
1. Electronics exam in 5 days → 3 sessions minimum, already scheduled.
2. Digital Logic Section on Wednesday → you have 2 section absences (max: 4).
   Do not miss this section.
3. You have 0 marks entered for Mathematics. Enter your last quiz score
   so I can recalibrate the plan.
═══════════════════════════════════════════════════
```

**Step 5 — Plan is stored and displayed:**

The plan is saved to a new `jarvis_study_plan` table. A new "PLAN" tab or card on the dashboard shows it. Each session card can be:
- ✅ Marked complete (moves to done, JARVIS logs actual study)
- 🔄 Rescheduled (moves to next available slot)
- ❌ Skipped (JARVIS notes it and re-weights next week)

**When to regenerate:**
- Every Sunday night automatically (new week)
- Any time you tap "Regenerate Plan" button
- Automatically after you upload a new past exam or log a new mark

**Feasibility: 100%. No new packages needed.**

---

### FEATURE 3: Subject Intelligence — Long-Term Memory

**The problem you identified:**
When you ask JARVIS about Electronics at the start of term vs. end of term, the AI has the same context window every time. It sees documents, but it doesn't "know" the subject the way a tutor who has reviewed all your past exams knows it. Also, with 6 subjects × multiple PDFs, the total context gets very long.

**The solution: Subject Intel Cards**

A new SQLite table `jarvis_subject_intel` stores one AI-generated "intelligence card" per subject. This is a compressed, high-value summary (~600 tokens) that Gemini generates by reading ALL uploaded documents for that subject. It contains:

```
SUBJECT: Electronics
Dr. Mohamed Samir — Engineering Faculty
Intel Card — Generated: Nov 10, updated: Nov 18

EXAM DNA:
- Midterms are always 4 questions: Q1 (Op-Amps), Q2 (Transfer Functions), 
  Q3 (Frequency Response), Q4 (varies — has been Filters 3 times).
- Dr. Samir always asks students to "sketch Bode plots" — never calculate 
  only. Must draw the plot.
- Marking: 5 marks for method, 5 for final answer. Correct method with 
  wrong arithmetic still earns 5/10.

TOP 5 HIGH-PROBABILITY TOPICS:
1. Transfer Functions — appeared in 5/5 past midterms (100%)
2. Op-Amp circuits (inverting/non-inverting) — 4/5 midterms (80%)
3. Bode Plot sketching — 4/5 midterms (80%)
4. RC Filters — 3/5 midterms (60%)
5. BJT Biasing — 2/5 midterms (40%), trending upward in recent exams

STUDENT STATUS:
- Current average: 71% (3 assessments entered)
- Trend: Declining (76% → 74% → 62%)
- Overdue topics: 4 (Transfer Functions, Bode Plots, Filters, BJT)
- Topics at Stage 0 (never reviewed): 3

DOCTOR'S PATTERN:
- Penalizes missing units in calculations (always specify Ω, F, H)
- Sheet problems map directly to exam problems (exam Q1 ≈ Sheet 2, Q5-8)
- Time pressure: 90 min for 4 questions — students report last Q often rushed
```

**When Intel Cards are generated:**
- First time automatically when you have ≥2 documents uploaded for a subject
- Every time you upload a new past exam or lecture PDF → card is refreshed
- Every Sunday as part of the weekly plan generation
- On demand: "JARVIS, refresh Electronics intel"

**How it helps:**
The intel card is always prepended to any AI call involving that subject. So instead of Gemini reading 15 PDFs every time (slow, expensive in tokens), it reads the compressed card (fast, accurate) plus whatever specific document is needed.

This is why JARVIS won't "forget" subject material at end of term — the intel card persists in SQLite and gets richer over time as you add more past exams.

**Feasibility: 100%. Uses existing `jarvis_documents` + `_generateContent()`.**

---

### FEATURE 4: Attendance Guardian

**The idea:** JARVIS actively tracks your absence risk and intervenes BEFORE it becomes a problem, not after.

---

**Level 1 — Real-time Warning (already exists, we enhance it)**

Current: Shows a notification when you hit max-1 absences.

Enhanced: When you log an absence that brings you to max-2 (two remaining), JARVIS speaks immediately via TTS:

```
"Noted. You now have 2 lecture absences in Digital Logic. 
 You have 2 remaining before you're barred from the final exam.
 Your next Digital Logic lecture is Thursday at 10 AM.
 I strongly advise attending."
```

**Level 2 — Tomorrow Morning Alert**

Every night at 9 PM, JARVIS checks: do you have a class tomorrow in a subject where you're at max-1 absences? If yes:

```
Notification title: "⚠️ MANDATORY CLASS TOMORROW"
Body: "Electronics lecture at 9 AM. You have 1 absence left. 
       Missing tomorrow bars you from the final. No exceptions."
```

This notification is a high-priority notification that cannot be swiped away without tapping (uses `Importance.max` with `ongoing: true` flag for Android).

**Level 3 — Day-of Class Reminder (already exists, enhanced)**

Current timetable notifications already fire before each class. We add absence context:

```
Current:  "Electronics lecture starts in 15 minutes — Building A, Room 204"
Enhanced: "Electronics lecture starts in 15 minutes — Room 204.
           You have 1 absence left for this subject. Do not be late."
```

**Level 4 — The Absence–Mark Collision Analysis (already built)**

`analyzeAbsenceMarkCollision()` already exists in brain service. We wire it to fire automatically when:
- You log a new absence AND your mark in that subject dropped in the last 2 assessments
- JARVIS generates a specific report showing the correlation

**Feasibility: 100%.**

---

### FEATURE 5: The Weekly Intelligence Briefing

**The idea:** Every Sunday at 8 PM, JARVIS generates a complete intelligence briefing for the coming week. This is not a notification — it's a full document that appears in the app, with a spoken summary you can play.

**What it contains:**

```
═══════════════════════════════════════════════════
WEEKLY INTEL BRIEFING — Week 12 of Semester
Generated by JARVIS — Sunday, Nov 17 at 20:00
═══════════════════════════════════════════════════

THIS WEEK'S THREAT ASSESSMENT:

🔴 CRITICAL — Electronics
   Exam in 5 days. Current average: 62%. Declining trend.
   4 overdue topics. 3 topics never reviewed.
   Required: minimum 4 study sessions this week.

🟠 URGENT — Digital Logic  
   Section absence count: 3/4. One more = barred.
   Wednesday section is NON-NEGOTIABLE.
   Midterm in 11 days. Stage distribution: 40% still at Stage 0.

🟡 WATCH — Networks
   No immediate exam, but 2 assignments due this week.
   Your average is 78% (stable). Keep momentum.

🟢 ON TRACK — Mathematics, Signals, Embedded Systems
   No critical issues detected. Continue normal review schedule.

─────────────────────────────────────────────────── 

A+ PROBABILITY THIS SEMESTER:

Electronics:    42% → needs 2 strong exam performances
Digital Logic:  61% → stable if section attendance maintained
Networks:       74% → on track
Mathematics:    ? → no marks entered yet (enter your quiz scores)
Signals:        68% → solid, one weak area (Fourier transforms)
Embedded:       71% → good

─────────────────────────────────────────────────── 

THIS WEEK'S MANDATORY ACTIONS (in order):

1. Electronics: study Transfer Functions + Op-Amps (Mon + Tue)
2. Do NOT miss Digital Logic section Wednesday
3. Complete Networks assignment due Thursday
4. Enter Mathematics quiz score (JARVIS cannot calibrate without it)
5. Upload Electronics past midterm 2022 if you have it

─────────────────────────────────────────────────── 

ONE THING:
If you do nothing else this week, prepare for the Electronics exam.
Every other subject can recover. A failed Electronics midterm
at this point puts A+ out of reach for the semester.

═══════════════════════════════════════════════════
```

**Delivery:** 
- Notification fires Sunday at 8 PM
- Tap notification → briefing document opens in a beautiful full-screen overlay
- "Play Briefing" button reads the summary aloud via TTS (the condensed version, ~60 seconds)
- Stored in app, accessible from dashboard anytime ("Last Intel Briefing" card)

**Feasibility: 100%.**

---

## Technical Summary

| Feature | New Packages Needed | New DB Tables | New Files |
|---------|-------------------|---------------|-----------|
| Auto-Launch (App Open) | None | None | Modify campus.dart |
| Auto-Launch (Scheduled Times) | None | None | New settings page |
| App Usage Watchdog | `app_usage`, `workmanager` | None | New service file |
| Study Schedule Builder | None | `jarvis_study_plan`, `jarvis_user_schedule` | New page + service |
| Subject Intel Cards | None | `jarvis_subject_intel` | Modify brain service |
| Attendance Guardian | None | None | Modify notifications.dart |
| Weekly Intelligence Briefing | None | `jarvis_weekly_briefing` | New overlay widget |

**Total new packages if App Usage Watchdog included:** 2  
**Total new packages if App Usage Watchdog excluded:** 0

---

## Implementation Order (Recommended)

**Phase 1 — Foundation (Build First)**
1. Subject Intel Cards — everything else depends on richer AI context
2. Study Schedule Builder — the core new feature you described
3. Auto-Launch on App Open — immediate wow factor

**Phase 2 — Intelligence Layer**
4. Weekly Intelligence Briefing — consolidates all data
5. Attendance Guardian enhancements — adds safety net
6. Scheduled Daily Check-ins — adds the time-trigger system

**Phase 3 — Optional**
7. App Usage Watchdog — Android only, requires manual permission setup

---

## Scenarios — What Life Looks Like After This

**Monday morning, 7:00 AM:**
Phone buzzes. *"JARVIS — Morning Brief Ready. Electronics lecture at 9. You have 1 absence left. Tap to hear your plan."* You tap. App opens. JARVIS speaks for 30 seconds. You know exactly what today requires before you've had breakfast.

**Monday, opens app at 8:45 AM:**
JARVIS speaks immediately: *"Electronics in 15 minutes, Room 204. You have 1 lecture absence left. Do not be late."* You did not have to check anything.

**Monday evening, 6:00 PM (study session starts):**
You open app. Plan says: *"18:00 — Electronics — Transfer Functions — 45 min. This topic is in 3 of 5 past midterms."* You tap it, start the Cognitive Reactor, study that specific topic.

**Wednesday, you miss Digital Logic section:**
You open app to log the absence. JARVIS speaks: *"Noted. You now have 4 section absences in Digital Logic. You are barred from the final exam. Contact Dr. Adel or the department immediately."*

**Sunday night:**
Weekly Intel Briefing notification fires. You read it. You know exactly what the coming week requires. You did not have to think about it.

**End of term:**
You ask JARVIS about a topic from Electronics that was discussed in week 3. His intel card still has it. He answers precisely, referencing the specific past exam it appeared in. He did not forget.

---

## Your Decision Points

Before I build anything, confirm these choices:

1. **App Usage Watchdog** — include it or skip it?
2. **Study schedule session length** — default 45 minutes, or different?
3. **Auto-launch briefing** — speak automatically on app open (TTS fires immediately), or show a card that you tap to hear?
4. **Weekly briefing day/time** — Sunday 8 PM is my recommendation. Your preference?
5. **Language** — briefings in English only, Arabic only, or auto-detect based on time/context (like the existing read_my_day does)?

Approve, edit, or redirect — then I build.
