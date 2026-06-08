import re
import os

# Territory transforms extracted from grep output
territories = {
    "afghanistan": (526.4506, 0, 142.3833),
    "alaska": (-70, 0, -100),
    "alberta": (150, 0, 130),
    "argentina": (209, 0, 290),
    "brazil": (250, 0, 270),
    "central_america": (170, 0, 210),
    "china": (522.4922, 0, 150.60211),
    "congo": (-647.67834, 0, 148.81306),
    "eastern_australia": (689.0634, 0, 357.92047),
    "eastern_unitedstates": (180, 0, 150),
    "egypt": (-628.968, 0, 239.85211),
    "east_africa": (-426.09222, 0, 130.17517),
    "greenland": (250, 0, 60),
    "great_britain": (-658.1514, 0, 343.92416),
    "iceland": (-847.443, 0, -226.425),
    "india": (599.18475, 0, 215.83804),
    "indonesia": (487.71255, 0, 248.315),
    "irkutsk": (575.022, 0, 107.132),
    "japan": (908.4478, 0, 221.62698),
    "kamchatka": (437.97055, 0, 62.661865),
    "madagascar": (737.8709, 0, 462.97992),
    "middle_east": (448.66376, 0, 175.3692),
    "mongolia": (545.95233, 0, 116.788025),
    "new_guinea": (761.9366, 0, 320.27676),
    "northern_europe": (-781.3559, 0, -254.92178),
    "northwest_territory": (110, 0, 70),
    "ontario": (260, 0, 180),
    "north_africa": (364.7779, 0, 200.44647),
    "peru": (330, 0, 410),
    "quebec": (370, 0, 190),
    "scandinavia": (-536.2432, 0, 331.54736),
    "siam": (710.6372, 0, 262.37692),
    "siberia": (631.80286, 0, 97.55832),
    "south_africa": (540.2059, 0, 390.61002),
    "southern_europe": (-744.22296, 0, -264.0796),
    "ukraine": (-433.68604, 0, 257.66913),
    "ural": (499.51495, 0, 99.52077),
    "venezuela": (330, 0, 340),
    "western_australia": (789.42834, 0, 437.94464),
    "western_europe": (-828, 0, 344),
    "western_united_states": (220, 0, 230),
    "yakutsk": (620.384, 0, 88),
}

# Calculate extents
x_coords = [t[0] for t in territories.values()]
z_coords = [t[2] for t in territories.values()]

min_x = min(x_coords)
max_x = max(x_coords)
min_z = min(z_coords)
max_z = max(z_coords)

width = max_x - min_x
depth = max_z - min_z

print("=== MAP WORLD EXTENT (Game Units) ===")
print(f"X range: {min_x:.2f} to {max_x:.2f} = {width:.2f} units wide")
print(f"Z range: {min_z:.2f} to {max_z:.2f} = {depth:.2f} units deep")
print(f"Center: ({(min_x + max_x)/2:.2f}, {(min_z + max_z)/2:.2f})")
print(f"Diagonal: {(width**2 + depth**2)**0.5:.2f} units")
print()
print(f"Extreme points:")
print(f"  Westernmost: {min([t for t in territories.items() if t[1][0] == min_x])}")
print(f"  Easternmost: {max([t for t in territories.items() if t[1][0] == max_x])}")
print(f"  Northernmost: {min([t for t in territories.items() if t[1][2] == min_z])}")
print(f"  Southernmost: {max([t for t in territories.items() if t[1][2] == max_z])}")
print()
print(f"Note: Projectile max_distance = 40464, implies half-diagonal ≈ 20232")
print(f"Actual half-diagonal: {(width**2 + depth**2)**0.5 / 2:.2f}")

