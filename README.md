# Configuration File Profiler
Automatically create a cluster profile in MATLAB for clusters using MATLAB Parallel Server and third-party schedulers, such as Slurm.
- This .m file is no way affiliated with MathWorks
- Uses the configuration file that comes with the official plugin/integration scripts
- Comes in a .m file that runs inside of MATLAB
- Supports R2012a-R2023b
- Is developed independently and is no way associated with MathWorks
- PluginScriptsLocation can be used to point to the individual script paths that need to be specified for R2016b and older
- Warnings about readability are necessary to make this function work for R2012a-R2016a. Please disregard them.

# Usage
- Download the latest release files or clone the repository
- Setup and edit a configuration file using one of the examples provided (exampleDesktop.conf)
- Place the configuration file in the same location as the integration_scripts_profiler.m file
- Run integration_scripts_profiler.m from MATLAB's Command Window
- Follow any prompts, if they are given
- You're hopefully then done!
