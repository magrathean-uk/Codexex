# How to Update [App Store Text Localizations](https://developer.apple.com/documentation/appstoreconnectapi/app_store/apps)

Running the following **download** command will create a folder with the dwn-*appleID* then create folders for *appInfo* and *platform* within at the specified folder path with files created for any of the locales that are currently on https://appstoreconnect.apple.com if applicable. Each locale file will have key value pairs for the current entries on the site. A metadata.txt file with the copyright value may be there if present on the site.
`xcrun altool --app-store-text ~/Downloads/TestApps/localization --download --apple-id <appleID>`
`--platform <platform> --bundle-short-version-string <CFBundleShortVersionString> --api-key <apiKey>`
`--api-issuer <issuerID>`

Running the following **upload** command will look for a folder matching up-*appleID* then look for the a matching platform folder and appInfo folder then go through any files named \<language-code\>.txt (for example: en-US.txt) that it can find within and parse their content to upload the changes to App Store Connect. To update attributes just edit a downloaded file with the new values or add any new attribute key value pairs. To add a new language just create a new file named \<language-code\>.txt (for example: en-AU.txt), and add the attribute key value pairs. To update the copyright create or edit the metadata.txt file.
`xcrun altool --app-store-text ~/Downloads/TestApps/localization --upload --apple-id <appleID>`
`--platform <platform> --bundle-short-version-string <CFBundleShortVersionString> --api-key <apiKey>`
`--api-issuer <issuerID>`

### Updatable Localizable Attribute Keys in a platform folder
* "promotionalText" _(170 char max)_  
	Promotional text lets you inform your App Store visitors of any current app features without requiring an updated submission. This text will appear above your description on the App Store for customers with devices running iOS 11 or later, and macOS 10.13 or later.
* "description" _required on new locale_  
	A description of your app, detailing features and functionality. 
* "keywords" _required on new locale (100 char max)_   
	Include one or more keywords that describe your app. Keywords make App Store search results more accurate. Separate keywords with an English comma, Chinese comma, or a mix of both.
* "supportUrl" _required on new locale_   
	A URL with support information for your app. This URL will be visible on the App Store.
* "marketingUrl"    
	A URL with marketing information about your app. This URL will be visible on the App Store.
* "whatsNew"  
	The App Store’s What’s New section is labeled “What’s New in your app”. It becomes open for editing when an app status is at ‘Prepare for Submission’ in App Store Connect.

### Other
* "copyright"  
	The name of the person or entity that owns the exclusive rights to your app, preceded by the year the rights were obtained (for example, "2008 Acme Inc."). Do not provide a URL.

### Language Codes
> "fr-FR", "he", "ko", "en-AU", "id", "fi", "de-DE", "ru", "hu", "en-US", "it", "pt-BR", "tr", "el", "ca", "sv", "no", "hi", "da", "pl", "zh-Hant", "pt-PT", "th", "ms", "cs", "sk", "zh-Hans", "es-MX", "vi", "fr-CA", "nl-NL", "uk", "es-ES", "ro", "en-GB", "ja", "hr", "ar-SA"

**NOTE**  
Quotes must be escaped for example "description" = "This next word has the \"quotes\" escaped.";

### Sample fr-FR.txt file
"promotionalText" = "Sed ut \"perspiciatis\" unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis"; 
"description" = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";  
"keywords" = "perferendis, doloribus, asperiores, repellat";  
"supportUrl" = "http://voluptas/nulla/pariatur.com";  
"marketingUrl" = "http://neque/porro/quisquam.com";  
 
### Sample metadata.txt file
"copyright" = "2008 Acme Inc."; 

# How to Update [App Info Localizations](https://developer.apple.com/documentation/appstoreconnectapi/app_store/app_metadata/app_info_localizations)

The app info attributes will be in files named \<language-code\>.txt (for example: ko.txt) within a folder named appInfo.  
New locales cannot be created from the appInfo they need to be created in app store text first. (for example: if I wanted to add a privatePolicyUrl for a new locale; I would need a \<language-code\>.txt file in both appInfo and the platform folder, with the required attribute keys.)
### Updatable Localizable Attribute Keys in the appInfo folder
#### General - App Information
* "name"  
	The name will be reviewed before it is made available on the App Store.
* "subtitle"  
	The subtitle will be reviewed before it is made available on the App Store.
	
#### Trust & Safety - App Privacy
* "privacyPolicyUrl"  
	A URL that links to your privacy policy. A privacy policy is required for all apps.
* "privacyPolicyText"   
	The Apple TV Privacy Policy will be reviewed before it is made available on the App Store.
	
### Sample fr-FR-app-info.txt file
"name" = "Le Nom";  
"subtitle" = "Sous-titre";  
"privacyPolicyUrl" = "http://politique/priv%C3%A9e";
"privacyPolicyText" = "http://politique-tv/priv%C3%A9e";

# How to Update [Beta App Store Text Localizations](https://developer.apple.com/documentation/appstoreconnectapi/prerelease_versions_and_beta_testers/beta_app_localizations)

The app info attributes will be in files named \<language-code\>.txt (for example: ko.txt) within the folder named appInfo.  
New locales cannot be created from appInfo the they need to be created in app store text first. (for example: if I wanted to add a privatePolicyUrl for a new locale; I would need a \<language-code\>.txt file in both appInfo and the platform folder, with the required attribute keys.)
`xcrun altool --beta-app-store-text ~/Downloads/TestApps/localization --upload --apple-id <appleID>`
`--platform <platform> --bundle-version <CFBundleVersion> --bundle-short-version-string <CFBundleShortVersionString>`
`--api-key <apiKey> --api-issuer <issuerID>`

### Beta App Localizable information that applies to all versions and platforms
* "description" _required on new locale (4000 char max)_  
    Provide a description of your app that highlights its features and functionality.
* "feedbackEmail" _required on new locale_   
    TestFlight Beta Testers can send feedback to this email address. It will also appear as the reply-to address for TestFlight invitation emails.
* "marketingUrl"    
    A URL with marketing information about your app. This URL will be visible on the App Store.
* "privacyPolicyUrl" _required on new locale_   
    A URL that links to your company’s privacy policy. Privacy policies are recommended for all apps that collect user or device related data or as otherwise required by law.
* "privacyPolicyText"    _(6000 char max)_  
    Privacy policies are required for apps that are Made for Kids or offer auto-renewable or free subscriptions. They’re also required for those with account registration, apps that access a user’s existing account, or as otherwise required by law. Privacy policies are recommended for apps that collect user- or device-related data.

### Beta App localizable information for a build version
* "whatsNew" _(4000 char max)_  
    Include information about what’s been added to this build, and what you would like your users to test.

