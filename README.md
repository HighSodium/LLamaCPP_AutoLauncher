# LLamaCPP_AutoLauncher

```text
~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ 
               _______ _______ _______                                                            
 |      |      |_____| |  |  | |_____|                                                            
 |_____ |_____ |     | |  |  | |     |                                                            
                                                                                                  
 _______ _     _ _______  _____             _______ _     _ __   _ _______ _     _ _______  ______
 |_____| |     |    |    |     | ___ |      |_____| |     | | \  | |       |_____| |______ |_____/
 |     | |_____|    |    |_____|     |_____ |     | |_____| |  \_| |_____  |     | |______ |    \_
                                                                                                  
~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
```

## Setup
- LLAMA.CPP releases - https://github.com/ggml-org/llama.cpp/releases
- Download and extract the llama.cpp release for your operating system from the link above into the `src` folder
- Download and extract the llama.cpp CUDA/Vulkan/ARM files from the link above into the `src` folder

## Usage
- Put GGUF model(s) in the `models` folder
- Run the `LAUNCHER.bat` file
- Follow onscreen instructions
- Profit

## MMPROJ (vision) and MTP (multi-token prediction) usage

### For models with built-in MTP heads
- Choose yes when it asks if the model is MTP

### For models with separate MTP files
- Rename the file to match the model name plus `mtp.gguf`
- Example: `MyFunModel_iQ8_ALPHA.mtp.gguf`

### For models with separate MMPROJ files
- Rename the file to match the model name plus `mmproj.gguf`
- Example: `MyFunModel_iQ8_ALPHA.mmproj.gguf`
