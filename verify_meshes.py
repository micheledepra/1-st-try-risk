import json

# Load Brazil GLTF to verify mesh properties
with open(r'c:\Users\mchld\OneDrive\Documents\1-st-try-risk\Assets\Territories\Vanilla\3D\brazil.gltf') as f:
    data = json.load(f)

bounds = data['accessors'][0]

print('Brazil mesh bounds:')
print(f'  X: {bounds["min"][0]:.2f} to {bounds["max"][0]:.2f} (width: {bounds["max"][0]-bounds["min"][0]:.2f}cm)')
print(f'  Y: {bounds["min"][1]:.2f} to {bounds["max"][1]:.2f} (thickness: {bounds["max"][1]-bounds["min"][1]:.2f}cm)')
print(f'  Z: {bounds["min"][2]:.2f} to {bounds["max"][2]:.2f} (height: {bounds["max"][2]-bounds["min"][2]:.2f}cm)')
print(f'\nCentered at origin: Y-axis center = {(bounds["min"][1] + bounds["max"][1])/2:.2f}')
print(f'Thickness verification: {"✓ PASS" if abs(bounds["max"][1]-bounds["min"][1] - 4.0) < 0.1 else "✗ FAIL"}')

# Check a few more territories
print('\n' + '='*50)
territories = ['afghanistan', 'alaska', 'india', 'japan']
for territory in territories:
    with open(rf'c:\Users\mchld\OneDrive\Documents\1-st-try-risk\Assets\Territories\Vanilla\3D\{territory}.gltf') as f:
        data = json.load(f)
    bounds = data['accessors'][0]
    y_thickness = bounds["max"][1] - bounds["min"][1]
    y_center = (bounds["min"][1] + bounds["max"][1]) / 2
    print(f'{territory.capitalize():20s} - Y thickness: {y_thickness:.2f}cm, centered: {abs(y_center) < 0.01}')
