class SourceService {
  SourceService();
}

/*
- Make a function that validates and standardizes github URLs, do the same for gitlab (fail = error)
- Make a function that gets the App title and Author name from a github URL, do the same for gitlab (can't fail)
- Make a function that takes a github URL and finds the latest APK release if any (with version), do the same for gitlab (fail = error)
- Make a function that takes a github URL and returns a README HTML if any, do the same for gitlab (fail = "no description")
- Make a function that looks for the first image in a README HTML and returns a small base64 encoded version of it (fail = generic icon)

- Make a function that integrates all above and returns an App object for a given github URL, do the same for gitlab

- Make a function that detects the URL (Github or Gitlab) and runs the right function above

- Make a function that can save/load an App object to/from persistent storage (JSON file with unique App ID as file name)

- Make a function (using the above fn) that loads an array of all Apps
*/