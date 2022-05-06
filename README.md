# Zeal's Shaders
A (future) bundle of HLSL shaders written for Reshade.

# Adaptive Rim Lighting
A rim lighting shader which exaggerates the effect of exposure around objects. In photography it is known as 3-point lighting, and it may be useful for cinematic use-cases.

## Notable Features
|Name|Description|
|-----|-----|
|Color|Adjust the Rim's tint.|
|Non-Adaptive|The strength of the rim will be constant everywhere.|
|Adaptive|The strength of the rim will depend on color emission in its environment.|
|Hybrid|The strength of the rim remains constant, unless a color in its environment generates a brighter emission.|
|Light Distance|Adjust the distance at which the rim will be affected by light emission.|
|Threshold|Increasing this will exclude the rim from adapting darker emissions.|

The shader also has parameters to compensate for reversed and flipped depth buffers.

## Examples
Notice the highlights on the creases of the curtains. This is produced by the Adaptive Rim Light shader.
![Final Result](https://github.com/bituq/ZealShaders/blob/master/Assets/RimLightImg1.jpg?raw=true/)
Below you can see an example of where the rims are located.
![Rim Pass](https://github.com/bituq/ZealShaders/blob/master/Assets/RimLightImg2.jpg?raw=true)
