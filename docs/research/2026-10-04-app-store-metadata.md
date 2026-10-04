# App Store metadata guidance

Verified against Apple's official documentation on October 4, 2026.

## Field limits

- Promotional text: 170 characters; displayed above the description; can be changed without a new app version.
- Description: 4,000 characters; plain text and line breaks, without HTML. Apple says it is used in web search engine results after release.
- Keywords: App Store Connect Help specifies 100 **bytes**, although Apple's marketing guidance describes 100 characters. Use an ASCII keyword string to satisfy both. Help also says each keyword must exceed two characters.

Source: [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

## Search and keyword choices

Apple lists title, subtitle, keywords, and primary category among text relevance factors. Both primary and secondary categories are indexed. Promotional text does not affect search ranking.

Choose terms that accurately describe actual functionality and match likely user searches. Separate terms with commas without spaces around commas; phrases may contain internal spaces. Avoid repeating title, subtitle, or category words, singular/plural variants, filler words, broad generic terms, or unnecessary special characters. Competitor names, irrelevant terms, and unauthorized protected names are prohibited. Less competitive niche terms may be more practical for a new app than broad popular terms. Monitor impressions, downloads, and conversion in App Analytics after launch.

Source: [App Store search](https://developer.apple.com/app-store/search/).

## Copy guidance

Use the description to explain benefits and help people decide to download. Apple recommends a concise opening paragraph followed by main features. The first sentence matters because people see it before expanding the description. Avoid unnecessary keyword stuffing and specific prices. Description changes normally accompany a new version.

Name and subtitle each allow 30 characters. Keep a memorable brand name; use the subtitle to communicate actual features or uses. Localize metadata for each target market rather than merely translating keyword lists literally.

Source: [Creating your product page](https://developer.apple.com/app-store/product-page/).

## Interpretation for drafting

Treat promotional text and description primarily as conversion copy. Use the name, subtitle, and keyword field together for relevant search coverage. Apple does not provide keyword search volume or difficulty figures here; any proposed list is a relevance-based starting hypothesis, not a proven ranking forecast. Finalize the keyword string against the actual submitted name, subtitle, and categories to avoid wasted repetition.
