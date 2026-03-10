import time
import re
import serial
from collections import deque
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import winsound
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D

# -----------------------------
# SERIAL SETTINGS
# -----------------------------
PORT = "COM4"
BAUD = 115200

ser = serial.Serial(
    port=PORT,
    baudrate=BAUD,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    bytesize=serial.EIGHTBITS,
    timeout=0.05
)

time.sleep(0.2)
ser.reset_input_buffer()

# -----------------------------
# PLOT SETTINGS
# -----------------------------
PLOT_DT = 0.05
UPDATE_MS = 50
SMOOTH_N = 100

THRESHOLD_C = 240.0
THRESHOLD_F = THRESHOLD_C * 9 / 5 + 32

# Keep *all* points so the whole run stays visible
MAX_POINTS = 200000  # ~ 2.7 hours at 0.05s spacing

times = deque(maxlen=MAX_POINTS)
temps = deque(maxlen=MAX_POINTS)
smooth_temps = deque(maxlen=MAX_POINTS)
states = deque(maxlen=MAX_POINTS)

count = 0
sum_temp = 0.0
min_temp = None
max_temp = None
alarm_active = False

current_unit = "C"       # assume C unless we see F
last_temp_val = None
last_state_val = None
last_plot_t = 0.0

t0 = time.time()

fig, ax = plt.subplots()
ax.grid(True)

# Colored temperature trace using a LineCollection.
temp_segments = LineCollection([], linewidths=2.0)
ax.add_collection(temp_segments)

(line_smooth,) = ax.plot([], [], linewidth=1.5, label=f"Moving Avg ({SMOOTH_N})")

stats_text = ax.text(0.02, 0.95, "", transform=ax.transAxes, va="top")
alarm_text = ax.text(0.02, 0.10, "", transform=ax.transAxes, va="top")

event_lines = []
MAX_EVENT_LINES = 500

# -----------------------------
# REGEX PARSERS
# -----------------------------
state_re = re.compile(r"\bS\s*[:= ]\s*(\d+)\b", re.IGNORECASE)
temp_cf_re = re.compile(r"\b([CF])\s*[:= ]\s*([-+]?\d+(?:\.\d+)?)\b", re.IGNORECASE)

def reset_everything(new_unit):
    global count, sum_temp, min_temp, max_temp, alarm_active
    global last_temp_val, last_plot_t, last_state_val

    for ln in event_lines:
        try:
            ln.remove()
        except Exception:
            pass
    event_lines.clear()

    times.clear()
    temps.clear()
    smooth_temps.clear()
    states.clear()

    count = 0
    sum_temp = 0.0
    min_temp = None
    max_temp = None
    alarm_active = False

    last_temp_val = None
    last_state_val = None
    last_plot_t = 0.0

    ax.set_ylabel(f"Temperature (°{new_unit})")
    ax.set_title(f"Temperature vs Time (°{new_unit})")

def moving_average_last(values, n):
    n = min(n, len(values))
    if n <= 0:
        return 0.0
    v = list(values)[-n:]
    return sum(v) / n

def parse_temp_and_state(line):
    s = line.strip()
    if not s:
        return None

    st = None
    ms = state_re.search(s)
    if ms:
        try:
            st = int(ms.group(1))
        except ValueError:
            st = None

    mt = temp_cf_re.search(s)
    if not mt:
        return None

    unit = mt.group(1).upper()
    try:
        temp_val = float(mt.group(2))
    except ValueError:
        return None

    return unit, temp_val, st

def add_event_vline(x, label, color=None):
    ln = ax.axvline(x, linestyle="--", linewidth=1.2, color=color)
    event_lines.append(ln)
    print(label)

    if len(event_lines) > MAX_EVENT_LINES:
        old = event_lines.pop(0)
        try:
            old.remove()
        except Exception:
            pass

STATE_COLORS = [
    "tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple",
    "tab:brown", "tab:pink", "tab:gray", "tab:olive", "tab:cyan"
]

def color_for_state(st):
    if st is None:
        return "k"
    return STATE_COLORS[st % len(STATE_COLORS)]

# -----------------------------
# LEGEND WITH YOUR STATE NAMES (0-5)
# -----------------------------
STATE_NAMES = {
    0: "Idle",
    1: "Preheat",
    2: "Soak",
    3: "Preflow",
    4: "Reflow",
    5: "Cooling",
}

# Keep the legend order 0..5
state_legend_handles = [
    Line2D([0], [0], color=color_for_state(st), lw=3, label=f"{st}: {STATE_NAMES[st]}")
    for st in range(6)
]

def update(_):
    global count, sum_temp, min_temp, max_temp, alarm_active
    global current_unit, last_temp_val, last_state_val, last_plot_t

    t = time.time() - t0
    latest = None

    # Read a bunch of lines per frame
    for _ in range(300):
        raw = ser.readline()
        if not raw:
            break
        s = raw.decode("utf-8", errors="ignore")
        parsed = parse_temp_and_state(s)
        if parsed:
            latest = parsed

    if latest is not None:
        unit, temp_val, st = latest

        if unit != current_unit:
            current_unit = unit
            reset_everything(current_unit)

        last_temp_val = temp_val

        if st is not None:
            if last_state_val is None:
                last_state_val = st
                add_event_vline(t, f"EVENT: STATE INIT -> {st} at t={t:.2f}s", color=color_for_state(st))
            elif st != last_state_val:
                prev = last_state_val
                last_state_val = st
                add_event_vline(t, f"EVENT: STATE {prev} -> {st} at t={t:.2f}s", color=color_for_state(st))

        threshold = THRESHOLD_C if current_unit == "C" else THRESHOLD_F

        count += 1
        sum_temp += temp_val
        min_temp = temp_val if (min_temp is None or temp_val < min_temp) else min_temp
        max_temp = temp_val if (max_temp is None or temp_val > max_temp) else max_temp
        avg_temp = sum_temp / count

        if temp_val >= threshold and not alarm_active:
            alarm_active = True
            add_event_vline(t, f"EVENT: ALARM ON at t={t:.2f}s, {temp_val:.2f} °{current_unit}", color="red")
            winsound.Beep(1500, 400)
        elif temp_val < (threshold - 0.2) and alarm_active:
            alarm_active = False
            add_event_vline(t, f"EVENT: ALARM OFF at t={t:.2f}s, {temp_val:.2f} °{current_unit}", color="green")

        if last_state_val is None:
            state_label = "-"
        else:
            state_label = f"{last_state_val}: {STATE_NAMES.get(last_state_val, 'Unknown')}"

        stats_text.set_text(
            f"Current: {temp_val:.2f} °{current_unit}\n"
            f"Min: {min_temp:.2f} °{current_unit}\n"
            f"Max: {max_temp:.2f} °{current_unit}\n"
            f"Avg: {avg_temp:.2f} °{current_unit}\n"
            f"State: {state_label}"
        )
        alarm_text.set_text(f"ALARM! >= {threshold:.1f} °{current_unit}" if alarm_active else "")

    # Add points at a fixed dt so time axis is "real"
    if last_temp_val is not None:
        while last_plot_t + PLOT_DT <= t:
            last_plot_t += PLOT_DT
            times.append(last_plot_t)
            temps.append(last_temp_val)
            smooth_temps.append(moving_average_last(temps, SMOOTH_N))
            states.append(last_state_val)

    # Update plots if we have data
    if len(times) >= 2:
        xs = list(times)
        ys = list(temps)
        sts = list(states)

        segs = []
        seg_colors = []
        for i in range(len(xs) - 1):
            segs.append([(xs[i], ys[i]), (xs[i+1], ys[i+1])])
            seg_colors.append(color_for_state(sts[i+1]))
        temp_segments.set_segments(segs)
        temp_segments.set_color(seg_colors)

        line_smooth.set_data(xs, list(smooth_temps))

        # ---- AUTOSCALE TO FULL DATA (NO SCROLLING WINDOW) ----
        ax.set_xlim(0, xs[-1] if xs[-1] > 1e-6 else 1.0)

        ymin = min(min(ys), min(smooth_temps))
        ymax = max(max(ys), max(smooth_temps))
        pad = max(0.5, 0.1 * (ymax - ymin))
        ax.set_ylim(ymin - pad, ymax + pad)
    else:
        ax.set_xlim(0, 10)

    return (temp_segments, line_smooth, stats_text, alarm_text)

ax.set_xlabel("Time (s)")
ax.set_title("Reflow Oven Temp vs. Time")
ax.set_ylabel("Temperature")

# Legend: smooth line + your named states (0-5)
ax.legend(handles=[line_smooth] + state_legend_handles, loc="lower right", fontsize=8, ncol=2)

ani = animation.FuncAnimation(
    fig, update,
    interval=UPDATE_MS,
    blit=False,
    cache_frame_data=False
)

try:
    print(f"Reading from {PORT} at {BAUD} baud... (close window to stop)")
    print("Expected lines like: S:2 C:154")
    plt.show()
finally:
    ser.close()
    print("Serial port closed.")
