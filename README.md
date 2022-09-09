# RenderFFI

This metaproject compiles multiple rendering libraries and bundles them such that they are easy to use in an FFI (foreign function interface) setting.

## Dependencies

The build script is written in PowerShell (https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell).

Compiling the libraries requires reasonably recent versions of:

- Python (to compile OIDN)
- CMake
- A C++ compiler

## Compiling

```
pwsh ./make.ps1
```