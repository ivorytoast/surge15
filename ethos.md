# Surge — App Ethos

## What it's not

- **Not a GPS tracker.** Strava, Nike Run Club, Apple Fitness — those apps follow you wherever you go and log the trip. Surge doesn't care where you went. It cares how well you ran a specific thing.
- **Not an open-ended activity logger.** Surge has a calendar and session history, but it's always anchored to a specific route. The record isn't "you ran 3.2km this morning" — it's "you trained your 155m loop 7 times at this pace." The history is meaningful because it's tied to a repeatable track.
- **Not a passive social app.** No public feed, no leaderboards, no kudos from strangers. But sharing is intentional and powerful — a run club leader can create a route, share it with the group, and everyone trains the same track. Social through deliberate sharing, not broadcasting.

---

## Origin

The app came from a real problem: combining functional training with consistent, repeatable runs is genuinely hard. The places you can perform pull-ups, row 500 meters, or lunge 50 yards are not always suitable for a running plan integrated in.

You can always find somewhere to do burpees. But how do you run a consistent 500m from your local park, a gym, or the beach, and have it be the same every time?

Surge was built to answer that question.

---

## What it is

Surge is a **training tool for people who run and do functional work in the same session**.

The key insight: **you can run anywhere. You can't do functional exercises anywhere.**

You need a specific spot — a park, a gym floor, a stretch of beach — to do wall balls, lunges, rowing, or any equipment-based movement. That spot is your anchor point. Everything else in your session is built around it: the route starts and ends near it, the plan sequences your exercises there.

Surge solves the "how do I structure all of this" problem. You define the route (the running portion, whatever you can work with near your spot) and the plan (the exercise sequence). Then you train it, repeat it, and improve at the whole thing — not just the run, not just the workout, but the complete session.

---

## The two building blocks

**Route = the track.**
Any stretch, any length. You record it once — and the shorter, the better. A 50m loop is just as valid as a 500m loop. Surge counts laps and handles the distance math, so a short route can power a 1×, 2×, or 4× run depending on your plan. The user records the anchor path; Surge turns it into any distance you need.

**Plan = the full workout.**
An ordered list of exercises — which may or may not include a run. A plan might be: 1000m run, 20 burpees, 500m run, 10 pull-ups. Or it might have no running at all. The goal of a plan, just like a route, is to define something repeatable that you want to get better at over time.

Plans and routes are independent. You can surge with just a route, just a plan, or both together.

---

## The core loop

1. **Build a route** — record the shortest meaningful loop near your anchor point
2. **Build a plan** — define the exercises (optional, but powerful)
3. **Hit the bolt** — run the route, work through the plan, Surge handles the tracking
4. **Come back** — repeat the same workout, improve over time

---

## The user

Someone who wants to be **genuinely fit** — not optimized for one thing.

They're not just training for a 5k. They're not just lifting. They want to run their route and then perform. They want to know if they're getting faster *and* stronger at the same workout — not just how far they went today.

They may have limited space. They definitely have a specific goal. And they want a tool that takes the math and structure off their plate so they can focus on the work.

---

## Design principles

- **Route first, always.** The route is the unit of running. Everything else is built around it.
- **Short routes are better routes.** The shorter the loop, the more versatile it is. Surge handles laps and distance scaling — don't make the user do that math.
- **Plans are the full picture.** A plan without a route is still a valid workout. A route without a plan is still a valid run. Together they're the complete session.
- **No friction at start.** When it's time to train, getting into a session should take seconds. The bolt tab is the hub — everything starts there.
- **The math is invisible.** Lap counting, distance conversion, exercise sequencing — Surge handles all of it.
- **Small spaces are valid.** The app should never make you feel like you need a "real" track or a "real" gym.
- **You choose the anchor.** Your favorite park, a sports field, the beach — wherever functional work is possible, that's your starting point.

---

## Onboarding messaging (current)

The onboarding flow uses these core messages, in order:

**Intro (phase 0):** "Train Where You Are" — functional training and repeatable runs are hard to combine. You pick the anchor point. Everything else starts from there.

**Routes (phase 1):** Highlight the + button. "Want to see how to create your first route?" — no forced action, just an invitation to tap.

**CreateRoute (phase 2):** "When You Are Ready: Tap 'Record'" — shortest loop possible, walk or run, time doesn't matter. User is never forced to record; "Got It" advances without recording.

**Plans (phase 3):** "Build Your First Plan" — tap + → New Plan, define a sequence of exercises, tap the bolt when ready to train.

**Surge Intent (phase 4):** "Your Main Hub" — every workout starts here, choose route / plan / both, user decides every session.

### Language rules for all user-facing copy
- Never use: "ethos", "hybrid athlete", "friend's garage"
- Keep the anchor metaphor: park, gym, beach — any place where functional work is possible

## Some other thoughts
- Making running a first class citizen of functional training
