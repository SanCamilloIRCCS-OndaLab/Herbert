# Herbert: an EEG Reproducible Brain Exploration Research Toolbox

This toolbox is still under development.

## What is Herbert?

Herbert is an open-source toolbox for building modular pipelines for connectivity and network analysis of resting-state M/EEG data.

The design allows (and encourages) the development of multiverse pipelines, where each branch can explore the effects of different parameters or algorithms within the same pipeline.

The pipeline steps are built as wrapper of state-of-the-art libraries, ensuring the reliability of the outcomes. 

Currently, Herbert is implemented as a Matlab toolbox. However, future plans include a Python implementation.

### Why *Herbert*?

Following open source tradition, the name is a recursive acronym: Herbert: an EEG Reproducible Brain Exploration Research Toolbox.

Moreover, Herbert is a homage to the fictional writer Herbert Quain, from Jorge Luis Borges. Quain is the author of a “regressive, ramified novel” in which the first chapter branches into three parallel chapters, each of which then branches again into three further chapters, resulting in a total of nine distinct stories.

In *Examination of the Work of Herbert Quain*, Borges closes with the following passage:

> I do not know if I should mention that once *April March* was published, Quain regretted the ternary order and predicted that whoever would imitate him would choose a binary arrangement. \
And that demiurges and gods would choose an infinite scheme: infinite stories, infinitely divided.

## Install

To install the software, you need git (downloadable releases will be provided in the future).

If you don't have git on your computer, you can follow for example [this tutorial](https://github.com/git-guides/install-git).

Once git is installed, go to the folder where you want to install the toolbox and run:

```bash
git clone --recurse-submodules https://github.com/SanCamillo-NeurophysiologyLab/SuperPipelineMultiverseAnalysis.git
```

It is very important to add `--recurse-submodules` to the command, since all the external dependencies are included as submodules!

## Pipeline structure
The pipeline is structured in 5 main modules:

1. Preprocessing
2. Head Model
3. Source Estimation
4. Connectivity Analysis
5. Network Analysis

Each module consists of multiple steps (implemented as Matlab functions), each of which is highly customizable.

The goal is to have a pipeline with default steps to run coherent analysis over different sets of data. This toolbox is intended to support analysis workflows: it automates many steps while keeping critical points under human supervision.

## Dependencies
The pipeline is developed with `Matlab 2022b`.

It also builds upon several open-source packages:

| Package   | Version  |
| ---       | ---      |
| [EEGLAB](https://github.com/sccn/eeglab) | 2024.2 |

The external dependencies are included as submodules in the folder `external`

## Code structure
The code is structured in a modular way, where each function can be used as it is, or combined with other functions to build up a complete pipeline.

The file `Herbert.m` is just a template to build a pipeline.

The pipeline is defined using a JSON or YAML file, structured as follows:

#### Pipeline JSON

```json
{
	"step1": {
        "function": "HRB_resample",
		"name": "downsampling",
        "save": true,
		"params": {
		    "Frequency": 250
        }
	},
	"step2.5": [
        {
		"function": "HRB_filter",
        "name": "bandpass",
        "save": true,
		"params": {
            "Type": "bandpass",
            "LowCutoff": 0.5,
            "HighCutoff": 48
            }        
	    },
        {
		"function": "HRB_filter",
        "name": "lowpass",
		"params": {
            "Type": "lowpass",
            "HighCutoff": 48
            }
	    }
    ],
    "step30": {
        "function": "HRB_removeChannels",
        "params": {
            "Channels": ["E67","E73","E82","E91","E92","E102","E111","E120","E133","E145","E165","E174","E187","E199","E208","E209","E216","E217","E218","E219","E225","E226","E227","E228","E229","E230","E231","E232","E233","E234","E235","E236","E237","E238","E239","E240","E241","E242","E243","E244","E245","E246","E247","E248","E249","E250","E251","E252","E253","E254","E255","E256"]
        }
    },
    "step4": {
        "function": "HRB_selectTime",
        "params": {
            "AfterStart": 5,
            "BeforeEnd": 5
        }
    },
    "step5": {
        "function": "HRB_cleanData",
        "save": true,
        "params": {
            "Severity": "loose"
        }
    }
}
```

#### Pipeline YAML
```yaml
step1:
  function: HRB_resample
  name: downsampling
  save: true
  params:
    Frequency: 250

step2:
  - function: HRB_filter
    name: bandpass
    save: true
    params:
      Type: bandpass
      LowCutoff: 0.5
      HighCutoff: 48
  - function: HRB_filter
    name: lowpass
    params:
      Type: lowpass
      HighCutoff: 48

step3:
  function: HRB_removeChannels
  params:
    Channels: ["E67","E73","E82","E91","E92","E102","E111","E120","E133","E145","E165","E174","E187","E199","E208","E209","E216","E217","E218","E219","E225","E226","E227","E228","E229","E230","E231","E232","E233","E234","E235","E236","E237","E238","E239","E240","E241","E242","E243","E244","E245","E246","E247","E248","E249","E250","E251","E252","E253","E254","E255","E256"]

step4:
  function: HRB_selectTime
  params:
    AfterStart: 5
    BeforeEnd: 5

step5:
  function: HRB_cleanData
  save: true
  params:
    Severity: loose
```
The `functions` directory stores one subdirectory for each of the included modules. Each of the module-subdirectory contains all the functions that implement the developed steps.

All the functions have the prefix `HRB_` in order to avoid conflicts with other Matlab packages.

## Settings

The toolbox works out of the box with default parameters. No parameter is hardcoded; all defaults are stored in `functions/0_misc/HRB_defaultConfig`.

The internal structure of the parameters is a Matlab nested struct where the first level is the name of the module, the second the name of the function , and finally the name of the parameter. The full list of default configurations is listed in the following table:

| Module        | Function      | Parameter     | Value |
| ---           | ---           | ---           | ---   |
| general       | -             | customConfigFileName | HRB_config |
| preprocessing | resample      | Frequency     | 250   |
| preprocessing | resample      | Save          | false   |
| preprocessing | filter        | Type          | bandpass   |
| preprocessing | filter        | LowCutoff     | 0.5   |
| preprocessing | filter        | HighCutoff    | 48   |
| preprocessing | filter        | Save          | false   |

## Roadmap

- [x] Core multiverse functions
- [x] Plot diagram
- [x] Preprocessing module
- [ ] Head Model module
- [ ] Source Estimation module
- [ ] Connectivity Analysis module
- [ ] Network Analysis module
- [ ] Python library