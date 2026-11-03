# Research basis

Checkpoint is **informed by** research on ADHD, executive function and time perception. It has **not** been tested in a study, so it shouldn't be described as evidence-based. This page maps each design choice to the evidence behind it and says how strong that evidence is.

Most of the strongest evidence comes from studies of **children** (especially classroom self-monitoring) or from general psychology rather than adult ADHD specifically. Citations were checked against abstracts and publisher or repository records; full texts weren't all reviewed, so specific figures should be confirmed against the original papers before quoting them elsewhere.

## Summary

| Design choice | Evidence | Strength |
|---|---|---|
| Show the real time and elapsed time | Timing deficits in ADHD are well documented across many studies | Strong for the problem; the fix is clinical recommendation |
| Interrupt at **unpredictable** intervals with a self-check | Cued self-monitoring of on-task behaviour is effective for children with ADHD | Strong in children; little direct adult evidence |
| Prompt and remind with the current objective | Goal cues speed resumption after interruption; if-then plans help goal attainment, including in children with ADHD | Moderate; Checkpoint's objective is a goal reminder, not yet an if-then plan |
| Organising and planning; reducing distractibility | CBT for adult ADHD (Safren et al.) outperformed an active control in medicated adults | Strong for the CBT program as a whole, not for any single app feature |
| Optional breathing cue | Slow breathing raises vagally mediated heart rate variability | Good evidence for the physiology; none for this small optional cue's effect on frustration |
| Estimate vs actual (planned, #11) | Time-skill training studies in children and adolescents with ADHD | Preliminary |

## Details

### Time perception is impaired in ADHD
Meta-analyses find timing deficits in ADHD across paradigms such as time discrimination, reproduction and estimation, though results vary by task. Marx and colleagues (2021) concluded there is "meta-analytic evidence of a broad range of timing deficits in persons with ADHD"; Zheng and colleagues (2020) found the same in children and adolescents.

"Time blindness" is a descriptive term popularised by Russell Barkley, not a diagnosis. His executive-function model of ADHD treats it as a disorder of *performing* what you know rather than *knowing* what to do, and his best-known practical recommendation is to **externalise time at the point of performance**: make time visible where the work happens instead of relying on internal tracking. Checkpoint's core idea follows this recommendation. It is widely endorsed clinically, but rigorous trials of specific time aids in adults are scarce.

### Cued self-monitoring
In self-monitoring interventions, a cue (often a tone at unpredictable intervals) prompts the person to ask whether they're on task and record the answer. A meta-analysis of self-regulation interventions for children with ADHD (Reid, Trout & Schartz, 2005) reported combined effect sizes above 1.0 for on-task behaviour, inappropriate behaviour, and academic accuracy and productivity. This is the closest evidence to Checkpoint's mechanism. Two caveats: it comes mostly from children in classrooms, and in at least one small study gains didn't persist once the cues were withdrawn, which argues for keeping the cue rather than expecting the habit to stick on its own.

Varying the interval (jitter) follows the same studies' practice of unpredictable cues, so the prompt can't be anticipated and braced for.

### Objectives, if-then plans and resuming work
- **If-then plans (implementation intentions).** A meta-analysis of 94 independent tests found a medium-to-large effect on goal attainment, d = 0.65 (Gollwitzer & Sheeran, 2006). In children with ADHD, if-then plans improved response inhibition on a Go/No-Go task to the level of children without ADHD (Gawrilow & Gollwitzer, 2008). An implementation intention is a specific **"If situation X, then I will do Y"** plan. Showing a goal statement is a useful reminder but not the same thing; see #32 for adding a real if-then step.
- **Resuming after an interruption.** The memory-for-goals model (Altmann & Trafton, 2002) and follow-up experiments find that cues to the suspended goal shorten the time it takes to resume, and longer, more demanding interruptions lengthen it (Monk, Trafton & Boehm-Davis, 2008). Showing the objective on the card is that kind of cue, and keeping check-ins brief limits the cost of interrupting.

### CBT for adult ADHD
The most directly relevant adult evidence is the cognitive-behavioural program by Safren and colleagues (*Mastering Your Adult ADHD*). In a randomised trial of 86 adults already on medication who still had symptoms, 12 sessions of CBT beat relaxation with educational support (response 53% vs 23% on clinician global improvement; gains maintained at 6 and 12 months) (Safren et al., 2010).

The program's core modules cover organising and planning (systems for tracking appointments and tasks), **gauging attention span and "distractibility delay"**, modifying the environment, and adaptive thinking, with an optional module on procrastination. Checkpoint overlaps with parts of this, and the program suggests further features:
- **Interval matched to attention span:** the program has people gauge how long they can typically stay on task. Checkpoint's interval could be suggested from the user's own history (#33).
- **Distractibility delay:** writing a distracting thought down to deal with later instead of acting on it now. A "park it" field on the card would support this (#34).
- **Daily task list and priorities:** aligns with #21 (Top 3).
- **Adaptive thinking:** aligns with the spec's shame-free question language.

Checkpoint is not CBT and doesn't replace it; at best it's a between-sessions support for some of its skills.

### Breathing cue
A large meta-analysis (Laborde et al., 2022; 223 studies) found voluntary slow breathing increases vagally mediated heart rate variability during, immediately after, and after multi-session practice. That supports slow breathing as a calming technique in general. A small, optional pulsing circle on a check-in card is far from the tested protocols, so its effect on frustration is unknown.

### Estimating time
Time-skill training combined with time-assistive devices improved time-processing ability in a randomised trial of 38 children and adolescents (9–15) with ADHD (Wennberg, Janeslätt and colleagues), though the children didn't report better daily time management. Evidence for adults is preliminary. The planned estimate-vs-actual feature (#11) is plausible but unproven.

## Measuring whether Checkpoint helps
Because there's no direct evidence for the app itself, the most useful step is to let users see their own trend: time on task (#24), estimate vs actual (#11) and on-track responses (#12) over weeks.

## References
- Altmann, E. M., & Trafton, J. G. (2002). Memory for goals: An activation-based model. *Cognitive Science, 26*(1), 39–83.
- Barkley, R. A. (1997). *ADHD and the Nature of Self-Control*. Guilford Press.
- Gawrilow, C., & Gollwitzer, P. M. (2008). Implementation intentions facilitate response inhibition in children with ADHD. *Cognitive Therapy and Research, 32*, 261–280. [PDF](https://www.socmot.uni-konstanz.de/sites/default/files/08_Gawrilow_Gollwitzer_Implementation_intentions_facilit.pdf)
- Gollwitzer, P. M., & Sheeran, P. (2006). Implementation intentions and goal achievement: A meta-analysis of effects and processes. *Advances in Experimental Social Psychology, 38*, 69–119. [Record](https://kops.uni-konstanz.de/entities/publication/2e749bfb-8533-437c-8203-7e788c910c5f)
- Laborde, S., et al. (2022). Effects of voluntary slow breathing on heart rate and heart rate variability: A systematic review and a meta-analysis. *Neuroscience & Biobehavioral Reviews, 138*, 104711. [Record](https://pure.solent.ac.uk/en/publications/effects-of-voluntary-slow-breathing-on-heart-rate-and-heart-rate-/)
- Marx, I., Cortese, S., Kölch, M., & Hacker, T. (2021). Meta-analysis: Altered perceptual timing abilities in attention-deficit/hyperactivity disorder. *Journal of the American Academy of Child & Adolescent Psychiatry*. https://doi.org/10.1016/j.jaac.2021.12.004
- Monk, C. A., Trafton, J. G., & Boehm-Davis, D. A. (2008). The effect of interruption duration and demand on resuming suspended goals. *Journal of Experimental Psychology: Applied*. [PDF](https://www.interruptions.net/literature/Monk-JEPA08.pdf)
- Reid, R., Trout, A. L., & Schartz, M. (2005). Self-regulation interventions for children with attention deficit/hyperactivity disorder. *Exceptional Children, 71*(4), 361–377.
- Safren, S. A., et al. (2010). Cognitive behavioral therapy vs relaxation with educational support for medication-treated adults with ADHD and persistent symptoms: A randomized controlled trial. *JAMA, 304*(8), 875–880.
- Safren, S. A., Sprich, S. E., Perlman, C. A., & Otto, M. W. (2017). *Mastering Your Adult ADHD: A Cognitive-Behavioral Treatment Program, Client Workbook* (2nd ed.). Oxford University Press. [Publisher](https://academic.oup.com/book/1239)
- Wennberg, B., Janeslätt, G., et al. Time-skill training and time-assistive devices for children with ADHD aged 9–15: a randomised trial. See the Örebro University project page: [oru.se](https://www.oru.se/english/research/research-projects/rp/?rdb=p2281)
- Zheng, Q., et al. (2020). Time perception deficits in children and adolescents with ADHD: A meta-analysis. *Journal of Attention Disorders*.
