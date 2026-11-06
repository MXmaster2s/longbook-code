# App Store screenshots

Six images per platform, the same six in the same order on iPhone and Mac. The frames, headlines and
order are in `scripts/store-images.mts` (`FRAMES`); the upload order is in `scripts/asc-screenshots.mts`.
Change the list in the first and the file names in the second together.

## Run

1. `npm run store:captures` (or `-- --only ios|mac`) takes the sources from current code, on the US demo
   household, with nothing on screen. iPhone: its own 6.9-inch simulator, 1320 x 2868. Mac: an offscreen
   build under its own bundle id, 2880 x 1800, so the maintainer's app and data are never read.
2. `npm run store:images` frames them on white under their headlines with headless Chrome.
3. Look at every one of the 12 images. Then `npm run asc:screenshots -- --check`, and only with the
   maintainer's go-ahead `npm run asc:screenshots`, which replaces the sets on both listings.

Recapture whenever a screen in the set changes, and before every submission that carries a visible change.

## Rules for what the images say

- The first three images carry the case alone; most shoppers see only those.
- Headline names what the person gets, in plain words; the line under it adds one fact. No prices, no
  "subscription tracker", no claims the build does not meet (accessibility labels are not claimed).
- Use the screen names the build shows (Proposals, AI Connections, People); a renamed label changes
  the headline in the same pull request.
- The Mac set shows Calendar where the iPhone shows AI Connections, because AI Connections lives in
  Settings on the Mac.
- Only the demo household appears: no real names, accounts or amounts. Check the images for text that
  is not the demo household before uploading.
- Every capture is dark; the frame sets it on white.
- Proposals is captured last, from its own copy of the folder, because the harness writes Claude's
  proposal into the folder it reads.
