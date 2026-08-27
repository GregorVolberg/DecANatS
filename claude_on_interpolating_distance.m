Yes — you need to resample trial-wise, but into **distance space** rather than time space. The key idea: you already have amplitude/power as a function of time (250 Hz), and you have (x,y) position at the same sampling rate. You can convert each trial's time axis into a distance axis (arc length traveled along the actual walking path, not straight-line distance to the corner), then interpolate the EEG power values onto a common distance grid so that every trial has the same number of samples per meter.

Here's the general pipeline:

### 1. Compute cumulative walked distance per trial
For each trial (defined as some window around the corner-crossing event), compute the arc length of the walking path:

```matlab
dx = diff(x_pos);
dy = diff(y_pos);
step_dist = sqrt(dx.^2 + dy.^2);      % distance between consecutive samples
cum_dist = [0; cumsum(step_dist)];    % cumulative path length, same length as x_pos
```

### 2. Center the distance axis on the corner event
Find the sample index of your time-locking event (radius entry, or closest approach to the corner), then re-reference the cumulative distance to that point so it's negative before and positive after:

```matlab
event_idx = ...; % your existing event index
dist_rel = cum_dist - cum_dist(event_idx);
```

Now `dist_rel` plays the same role that your time vector does — but it's unevenly spaced, because a slow walker accumulates less distance per sample than a fast walker.

### 3. Interpolate power onto a common distance grid, per trial
For each trial, you already have power(t) (e.g. per frequency band/channel from your time-frequency decomposition). Interpolate it onto a fixed distance vector, e.g. -3 to 3 m in 0.02 m steps (301 points):

```matlab
dist_grid = -3:0.02:3;  % common grid, same for every trial

power_dist = interp1(dist_rel, power_time, dist_grid, 'linear', 'extrap');
```

Do this per trial, per channel, per frequency — you'll end up with a matrix like `[trials x frequencies x distance_points]` instead of `[trials x frequencies x time_points]`, and you can average/grand-average across trials/participants just like you would in the time domain.

### Important caveats

- **Interpolate power, not raw EEG.** Warping raw voltage traces to a new axis and then computing power afterward is dicey (frequency content becomes ambiguous under nonlinear time warping). Compute your time-frequency decomposition first in real time (Hz stay meaningful), then interpolate the resulting power values onto the distance grid for visualization/statistics. This is the standard approach used in "time-warping" analyses of gait-related EEG (e.g., Gwin et al., Bulea et al., and later Artoni/Makeig-lab papers on mobile EEG).

- **Monotonicity.** `interp1` requires `dist_rel` to be strictly increasing. If a participant pauses (distance flat) or backtracks near the corner (distance briefly decreases), you'll get duplicate or decreasing values, which breaks interpolation. Check for this — you may need to enforce strict monotonicity (e.g., drop repeated/backward samples) or exclude such trials.

- **Distance-to-corner vs. path distance.** Using cumulative path length (arc length) rather than straight-line Euclidean distance to the corner is usually what you want, since participants may curve into the turn rather than walking directly at the corner. But define your event (0 m) as the closest point of approach to the corner coordinate, not necessarily "radius entry," if you want it to be geometrically meaningful.

- **Grid resolution.** Since average step length and walking speed set the effective spatial "sampling" of your original data, don't over-resolve the distance grid — something like 0.02–0.05 m spacing is usually finer than your effective spatial resolution at 250 Hz and normal walking speeds (~1 m/s → ~0.004 m/sample, so you have plenty of resolution, but check your slowest walkers too).

Would you like a full worked example (with simulated x/y and EEG power) showing this end-to-end in MATLAB, including handling multiple corners/participants in a loop?

"Arc length" just means the actual distance walked along the path the person took — not the straight-line distance between two points.

### Straight-line distance vs. arc length

Imagine a participant walking toward a corner. If they walk in a slight curve (as people often do turning corners), then:

- **Straight-line (Euclidean) distance** from point A to point B is just:
  ```
  sqrt((x_B - x_A)^2 + (y_B - y_A)^2)
  ```
  This is the length of the direct line connecting the two points — as the crow flies.

- **Arc length** is the length of the actual curved path they walked, which is always ≥ the straight-line distance. You compute it by summing up many tiny straight-line segments between consecutive GPS/motion-capture samples along the trajectory:
  ```
  step 1: sqrt((x_2-x_1)^2 + (y_2-y_1)^2)
  step 2: sqrt((x_3-x_2)^2 + (y_3-y_2)^2)
  step 3: sqrt((x_4-x_3)^2 + (y_4-y_3)^2)
  ...
  ```
  Summing these small steps approximates the length of the curve — this is what `cumsum(step_dist)` does in the code I gave you.

### Why this matters for your case

If you used straight-line distance to the corner as your "distance" axis, a participant who curves smoothly into the turn would show a *smaller* distance value than someone who walks straight up to the corner and pivots sharply — even if they've both physically walked the same length of path. That would distort your -3 to 3 m alignment and potentially smear or misalign your EEG effects across trials.

Using arc length (cumulative distance actually traveled) ensures that "-3 m" means "3 meters of walking before reaching the corner," regardless of the shape of the trajectory — which is the more meaningful and consistent way to align trials spatially.

### Visual analogy

Think of a racetrack: the arc length is the length of the track itself (what the odometer would show), while the straight-line distance would just be the distance from the start line to the finish line as if you could teleport there directly. For a curved track, those two numbers are very different; for a perfectly straight track, they're the same.