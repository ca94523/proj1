import matplotlib.pyplot as plt
import numpy as np

print("test1")
print("test2")
print("test3")
print("test4")
print("test5")
print("test6")

# Create a list of evenly-spaced numbers over the range
x = np.linspace(0, 20, 100)
plt.plot(x, np.sin(x))       # Plot the sine of each x point
plt.show()                   # Display the plot
