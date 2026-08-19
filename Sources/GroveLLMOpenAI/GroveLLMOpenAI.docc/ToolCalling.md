# Tool Calling

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#       
-->

Letting a model call into your app.

## Overview

A model can be given [tools](https://platform.openai.com/docs/guides/function-calling) to call: named pieces of your app it may invoke, with arguments it fills in, whose results come back to it as part of the conversation. <!-- markdown-link-check-disable-line -->
``GroveLLMOpenAI`` expresses them as ordinary Swift types, so a tool reads as a function with its parameters declared inline.

- Note: The wire format calls each one a `function` — one *kind* of tool. Everything the model may be offered is a tool, which is what these types are named for.

## Usage

The tool calling mechanism reflected within the DSL of ``GroveLLMOpenAI`` consists of two main components: The ``LLMTool``, serving as a representative of the to-be executed function, and the ``LLMTool/Parameter``s, declaring which parameters the ``LLMTool`` receives from the LLM upon execution.

The crucial properties of a ``LLMTool`` are the ``LLMTool/name``, serving as the identifier of the function, as well as the ``LLMTool/description``, enabling the LLM to understand the purpose of the available tool call.
The actual logic that is executed upon a tool call by the LLM resides in the ``LLMTool/execute()`` function.
``LLMTool/execute()`` returns a `String?`, containing all the information the Grove application wants to provide to the LLM upon a tool call, and is automatically injected into the LLM conversation by ``GroveLLMOpenAI``.

The ``LLMTool/Parameter`` property wrapper (`@Parameter`) can be used within an ``LLMTool`` to declare that the function takes a number of arguments of specific type.
As the function is called by the LLM, the function parameters that are sent by the LLM are automatically injected into the ``LLMTool`` by ``GroveLLMOpenAI``.
The wrapper contains various initializers for the respective wrapped types of the parameter, such as `Int`, `Float`, `Double`, `Bool` or `String`, as well as `Optional`, `array`, and `enum` data types.
For these types, ``GroveLLMOpenAI`` is able to automatically synthezise the OpenAI function parameter schema from the declared ``LLMTool/Parameter``s.

> Tip: In case developers want to manually define schema's for custom and complex types, please refer to ``LLMToolParameter``, ``LLMToolParameterEnum``, and ``LLMToolParameterArrayElement``.

The available ``LLMTool``s are then declared via ``LLMOpenAILikeSchema``'s initializer, enabling the LLM to pick relevant functions and call them in order to receive more information or execute a specific programatic functionality.

### Example

A full code example of using a ``LLMTool`` using the ``LLMOpenAISchema`` (configuration of the LLM) can be found below.
As LLMs cannot access real time information, the OpenAI model is provided with a weather ``LLMTool``, enabling the LLM to fetch up-to-date weather information for a specific location.

```swift
// The defined `LLMTool` made available to the OpenAI LLM
struct WeatherFunction: LLMTool {
    static let name: String = "get_current_weather"
    static let description: String = "Get the current weather in a given location"

    @Parameter(description: "The city and state of the to be determined weather, e.g. San Francisco, CA")
    var location: String

    func execute() async throws -> String? {
        "The weather at \(location) is 30 degrees"
    }
}

// Enclosing view to display an LLM chat
struct LLMOpenAIChatTestView: View {
    private let schema = LLMOpenAISchema(
        parameters: .init(
            modelType: .gpt4o,
            systemPrompt: "You're a helpful assistant that answers questions from users."
        )
    ) {
        WeatherFunction()   // State which LLM functions are made available to the OpenAI LLM
    }

    var body: some View {
        LLMChatView(
            schema: schema
        )
    }
}
```

One can even argue that the LLM should be able to request the weather in a specific measuring scale.
This can be achieved by adding a second parameter, in this case a `String`-based `enum`, to the ``LLMTool``.
The `enum` type has to conform to the ``LLMToolParameterEnum`` protocol and needs to be `String`-based (so the `RawValue` must be a `String`).

```swift
struct LLMOpenAIFunctionWeather: LLMTool {
    // The `enum`-based type used as a tool call parameter
    enum TemperatureUnit: String, LLMToolParameterEnum {
        case celsius
        case fahrenheit
    }
    
    static let name: String = "get_current_weather"
    static let description: String = "Get the current weather in a given location"
    
    @Parameter(description: "The city and state of the to be determined weather, e.g. San Francisco, CA")
    var location: String
    @Parameter(description: "The unit of the temperature")
    var unit: TemperatureUnit   // Specify the `enum`-based type as a parameter
    
    func execute() async throws -> String? {
        "The weather at \(location) is 30 degrees \(unit)"
    }
}
```

In addition to that, the ``LLMTool/Parameter`` also enables the usage of `array`-based types with primitive array element types (such as `Int`s or `String`s) out of the box.
This can be incredibly useful if the specific use case requires the LLM to request lots of data from the client.

An example use case for this feature within the health context can be found in the example below.
The LLM is able to request specific types of health data which is then returned by the tool call.

```swift
struct LLMOpenAIFunctionHealthData: LLMTool {
    static let name: String = "get_health_data"
    static let description: String = "Get the health data of a patient based on health data types."
    
    @Parameter(description: "The types of health data that are requested", enum: ["allergies", "medications"])
    var healthDataTypes: [String]   // Use an `array` of `String`s as parameter
    
    func execute() async throws -> String? {
        var healthData = ""
        
        if healthDataTypes.contains(where: { $0 == "allergies" }) {
            healthData += "The patient has an allergy against nuts. "
        }
        if healthDataTypes.contains(where: { $0 == "medications" }) {
            healthData += "The patient takes painkillers twice a day. "
        }
        
        return healthData
    }
}
```

> Tip: In case one wants to use complex custom objects within the ``LLMTool/Parameter``, one can use ``LLMToolParameter`` for regular types and ``LLMToolParameterArrayElement`` for `array`-based types to manually specify the conformance of Swift types to the [OpenAI Function calling schema](https://platform.openai.com/docs/guides/function-calling). See the inline DocC documentation for further information. <!-- markdown-link-check-disable-line -->

## Topics

### LLM functions

- ``LLMTool``
- ``LLMTool/Parameter``
- ``LLMToolBuilder``

### Function Parameters

- ``LLMToolParameter``
- ``LLMToolParameterEnum``
- ``LLMToolParameterArrayElement``
