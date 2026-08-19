# ``GroveLocalization``

Work with localized resources.


## Overview

The GroveLocalization target implements localization-related facilities, for working with localized string and file resources.

It defines extensions on `Bundle` and `LocalizedStringResource` to enable applications to work with multiple/dynamic localizations at runtime, and implements a `LocalizedStringResource`-inspired ``LocalizedFileResource`` type for working with file-based localization. 


## Topics

### Working with Localized Strings
- ``Foundation/LocalizedStringResource/localizedString(for:)``
- ``Foundation/Bundle/localizedString(forKey:tables:)``
- ``Foundation/Bundle/localizedString(forKey:tables:localizations:)``
- ``Foundation/Bundle/preferredLocalizations(from:limitToPreferences:)``
- ``Foundation/Bundle/LocalizationLookupTable``
- ``Foundation/LocalizedStringResource/BundleDescription/atURL(from:)``

### Working with Localized File Resources
- ``LocalizedFileResource``
- ``LocalizationKey``
- ``LocalizedFileResolution``
- ``LocaleMatchingBehaviour``

