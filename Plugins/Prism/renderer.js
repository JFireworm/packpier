function resolveLanguage(preference, preferred = []) {
  if (["zh-CN", "zh-TW", "en", "ja", "ko"].includes(preference)) return preference;
  for (const tag of preferred) {
    const [language2, ...parts] = tag.trim().toLowerCase().replaceAll("_", "-").split("-");
    if (language2 === "zh") {
      for (const part of parts) {
        if (["hant", "tw", "hk", "mo"].includes(part)) return "zh-TW";
        if (part === "hans") break;
      }
      return "zh-CN";
    }
    if (["en", "ja", "ko"].includes(language2)) return language2;
  }
  return "en";
}

var strings = {
  "\u4F1A\u8BDD\u540C\u6B65\u4E2D\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5": ["Chat is syncing. Try again in a moment.", "\u6703\u8A71\u540C\u6B65\u4E2D\uFF0C\u8ACB\u7A0D\u5F8C\u518D\u8A66", "\u30C1\u30E3\u30C3\u30C8\u3092\u540C\u671F\u4E2D\u3067\u3059\u3002\u3057\u3070\u3089\u304F\u3057\u3066\u304B\u3089\u518D\u8A66\u884C\u3057\u3066\u304F\u3060\u3055\u3044\u3002", "\uCC44\uD305\uC744 \uB3D9\uAE30\uD654\uD558\uB294 \uC911\uC785\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD558\uC138\uC694."],
  "\u4F1A\u8BDD\u5C1A\u672A\u540C\u6B65\u5B8C\u6210": ["Chat has not finished syncing.", "\u6703\u8A71\u5C1A\u672A\u540C\u6B65\u5B8C\u6210", "\u30C1\u30E3\u30C3\u30C8\u306E\u540C\u671F\u304C\u5B8C\u4E86\u3057\u3066\u3044\u307E\u305B\u3093\u3002", "\uCC44\uD305 \uB3D9\uAE30\uD654\uAC00 \uC544\uC9C1 \uC644\uB8CC\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4."],
  "\u4F1A\u8BDD\u4E0D\u5728\u5F53\u524D\u6392\u884C\u699C": ["Chat is not in the current ranking.", "\u6703\u8A71\u4E0D\u5728\u76EE\u524D\u7684\u6392\u884C\u699C", "\u30C1\u30E3\u30C3\u30C8\u306F\u73FE\u5728\u306E\u30E9\u30F3\u30AD\u30F3\u30B0\u306B\u3042\u308A\u307E\u305B\u3093\u3002", "\uCC44\uD305\uC774 \uD604\uC7AC \uC21C\uC704\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4."],
  "\u4F1A\u8BDD\u4E3B\u9898\u8272": ["Chat color", "\u6703\u8A71\u4E3B\u984C\u8272", "\u30C1\u30E3\u30C3\u30C8\u306E\u30C6\u30FC\u30DE\u8272", "\uCC44\uD305 \uD14C\uB9C8 \uC0C9\uC0C1"],
  "\u9879\u76EE\u4E3B\u9898\u8272": ["Project color", "\u5C08\u6848\u4E3B\u984C\u8272", "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306E\u30C6\u30FC\u30DE\u8272", "\uD504\uB85C\uC81D\uD2B8 \uD14C\uB9C8 \uC0C9\uC0C1"],
  "\u7EE7\u627F\u9879\u76EE\u8272": ["Use project color", "\u6CBF\u7528\u5C08\u6848\u8272", "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306E\u8272\u3092\u7D99\u627F", "\uD504\uB85C\uC81D\uD2B8 \uC0C9\uC0C1 \uC0AC\uC6A9"],
  "\u6062\u590D\u9ED8\u8BA4\u8272": ["Reset to default", "\u9084\u539F\u9810\u8A2D\u8272", "\u65E2\u5B9A\u306E\u8272\u306B\u623B\u3059", "\uAE30\uBCF8 \uC0C9\uC0C1\uC73C\uB85C \uBCF5\uC6D0"],
  "\u6700\u8FD1\u4F7F\u7528": ["Recent", "\u6700\u8FD1\u4F7F\u7528", "\u6700\u8FD1\u4F7F\u3063\u305F\u8272", "\uCD5C\uADFC \uC0AC\uC6A9"],
  "\u81EA\u9009\u989C\u8272": ["Custom color", "\u81EA\u8A02\u984F\u8272", "\u30AB\u30B9\u30BF\u30E0\u30AB\u30E9\u30FC", "\uC0AC\uC6A9\uC790 \uC9C0\uC815 \uC0C9\uC0C1"],
  "\u8FD4\u56DE\u8272\u677F": ["Back to colors", "\u8FD4\u56DE\u8272\u76E4", "\u8272\u4E00\u89A7\u306B\u623B\u308B", "\uC0C9\uC0C1\uD45C\uB85C \uB3CC\uC544\uAC00\uAE30"],
  "\u8BBE\u7F6E\u4E3B\u9898\u8272": ["Set theme color", "\u8A2D\u5B9A\u4E3B\u984C\u8272", "\u30C6\u30FC\u30DE\u8272\u3092\u8A2D\u5B9A", "\uD14C\uB9C8 \uC0C9\uC0C1 \uC124\uC815"],
  "\u62D6\u52A8\u914D\u8272\u7A97\u53E3": ["Drag the color picker", "\u62D6\u66F3\u914D\u8272\u8996\u7A97", "\u30C9\u30E9\u30C3\u30B0\u3057\u3066\u79FB\u52D5", "\uC0C9\uC0C1 \uCC3D \uB4DC\uB798\uADF8"],
  "\u5173\u95ED": ["Close", "\u95DC\u9589", "\u9589\u3058\u308B", "\uB2EB\uAE30"],
  "\u8C03\u8272\u677F": ["Color picker", "\u8ABF\u8272\u76E4", "\u30AB\u30E9\u30FC\u30D4\u30C3\u30AB\u30FC", "\uC0C9\uC0C1 \uC120\uD0DD\uAE30"],
  "\u9884\u8BBE\u8272\u677F": ["Presets", "\u9810\u8A2D\u8272\u76E4", "\u30D7\u30EA\u30BB\u30C3\u30C8", "\uD504\uB9AC\uC14B"],
  "\u9009\u8272\u65B9\u5F0F": ["Color selection method", "\u9078\u8272\u65B9\u5F0F", "\u8272\u306E\u9078\u629E\u65B9\u6CD5", "\uC0C9\uC0C1 \uC120\uD0DD \uBC29\uC2DD"],
  "\u6362\u8272": ["Edit color", "\u63DB\u8272", "\u8272\u3092\u7DE8\u96C6", "\uC0C9\uC0C1 \uD3B8\uC9D1"],
  "\u7B2C {n} \u683C": ["Slot {n}", "\u7B2C {n} \u683C", "\u30B9\u30ED\u30C3\u30C8 {n}", "{n}\uBC88 \uCE78"],
  "\u6362\u8272\uFF0C\u7B2C {n} \u683C": ["Edit slot {n}", "\u7DE8\u8F2F\u7B2C {n} \u683C", "\u30B9\u30ED\u30C3\u30C8 {n} \u306E\u8272\u3092\u7DE8\u96C6", "{n}\uBC88 \uCE78 \uC0C9\uC0C1 \uD3B8\uC9D1"],
  "\u4FDD\u5B58\u5230\u7B2C {n} \u683C": ["Save to slot {n}", "\u5132\u5B58\u81F3\u7B2C {n} \u683C", "\u30B9\u30ED\u30C3\u30C8 {n} \u306B\u4FDD\u5B58", "{n}\uBC88 \uCE78\uC5D0 \uC800\uC7A5"],
  "\u5E94\u7528\u989C\u8272": ["Apply color", "\u5957\u7528\u984F\u8272", "\u8272\u3092\u9069\u7528", "\uC0C9\uC0C1 \uC801\uC6A9"],
  "\u5C4F\u5E55\u53D6\u8272": ["Pick from screen", "\u87A2\u5E55\u53D6\u8272", "\u753B\u9762\u304B\u3089\u8272\u3092\u53D6\u5F97", "\uD654\uBA74\uC5D0\uC11C \uC0C9\uC0C1 \uC120\uD0DD"],
  "\u7CFB\u7EDF\u9009\u8272": ["System picker", "\u7CFB\u7D71\u9078\u8272", "\u30B7\u30B9\u30C6\u30E0\u3067\u9078\u629E", "\uC2DC\uC2A4\uD15C \uC0C9\uC0C1 \uC120\uD0DD"],
  "\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668": ["System color picker", "\u7CFB\u7D71\u984F\u8272\u9078\u64C7\u5668", "\u30B7\u30B9\u30C6\u30E0\u30AB\u30E9\u30FC\u30D4\u30C3\u30AB\u30FC", "\uC2DC\uC2A4\uD15C \uC0C9\uC0C1 \uC120\uD0DD\uAE30"],
  "\u6253\u5F00\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668": ["Open system color picker", "\u958B\u555F\u7CFB\u7D71\u984F\u8272\u9078\u64C7\u5668", "\u30B7\u30B9\u30C6\u30E0\u30AB\u30E9\u30FC\u30D4\u30C3\u30AB\u30FC\u3092\u958B\u304F", "\uC2DC\uC2A4\uD15C \uC0C9\uC0C1 \uC120\uD0DD\uAE30 \uC5F4\uAE30"],
  "\u6B64\u7A97\u53E3\u65E0\u6CD5\u76F4\u63A5\u53D6\u6837\uFF0C\u53EF\u6539\u7528\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668\u3002": ["Use the system color picker in this window.", "\u6B64\u8996\u7A97\u8ACB\u6539\u7528\u7CFB\u7D71\u984F\u8272\u9078\u64C7\u5668\u3002", "\u3053\u306E\u30A6\u30A3\u30F3\u30C9\u30A6\u3067\u306F\u30B7\u30B9\u30C6\u30E0\u30AB\u30E9\u30FC\u30D4\u30C3\u30AB\u30FC\u3092\u4F7F\u7528\u3057\u3066\u304F\u3060\u3055\u3044\u3002", "\uC774 \uCC3D\uC5D0\uC11C\uB294 \uC2DC\uC2A4\uD15C \uC0C9\uC0C1 \uC120\uD0DD\uAE30\uB97C \uC0AC\uC6A9\uD558\uC138\uC694."],
  "\u8272\u76F8": ["Hue", "\u8272\u76F8", "\u8272\u76F8", "\uC0C9\uC870"],
  "\u5341\u516D\u8FDB\u5236\u989C\u8272": ["Hex color", "\u5341\u516D\u9032\u4F4D\u8272\u78BC", "16\u9032\u30AB\u30E9\u30FC\u30B3\u30FC\u30C9", "16\uC9C4\uC218 \uC0C9\uC0C1"],
  "\u9971\u548C\u5EA6\u548C\u660E\u5EA6\uFF0C\u65B9\u5411\u952E\u8C03\u6574": ["Saturation and brightness, use arrow keys", "\u98FD\u548C\u5EA6\u8207\u660E\u5EA6\uFF0C\u4EE5\u65B9\u5411\u9375\u8ABF\u6574", "\u5F69\u5EA6\u3068\u660E\u5EA6\u3001\u77E2\u5370\u30AD\u30FC\u3067\u8ABF\u6574", "\uCC44\uB3C4\uC640 \uBA85\uB3C4, \uBC29\uD5A5\uD0A4\uB85C \uC870\uC808"],
  "\u8BF7\u8F93\u5165\u516D\u4F4D HEX \u8272\u503C": ["Enter a six-digit HEX color", "\u8ACB\u8F38\u5165\u516D\u4F4D HEX \u8272\u78BC", "6\u6841\u306EHEX\u5024\u3092\u5165\u529B\u3057\u3066\u304F\u3060\u3055\u3044", "6\uC790\uB9AC HEX \uC0C9\uC0C1\uC744 \uC785\uB825\uD558\uC138\uC694"],
  "\u6392\u884C\u699C\u89C6\u56FE": ["Ranking view", "\u6392\u884C\u699C\u6AA2\u8996", "\u30E9\u30F3\u30AD\u30F3\u30B0\u8868\u793A", "\uC21C\uC704 \uBCF4\uAE30"],
  "\u7F6E\u9876\u5C55\u793A\u65B9\u5F0F": ["Pinned view", "\u7F6E\u9802\u986F\u793A\u65B9\u5F0F", "\u30D4\u30F3\u7559\u3081\u306E\u8868\u793A\u65B9\u6CD5", "\uACE0\uC815 \uD56D\uBAA9 \uD45C\uC2DC \uBC29\uC2DD"],
  "\u5168\u90E8\u4E00\u8D77\u6392\u5E8F": ["All pinned", "\u5168\u90E8\u4E00\u8D77\u6392\u5E8F", "\u3059\u3079\u3066\u307E\u3068\u3081\u3066\u8868\u793A", "\uBAA8\uB450 \uD568\uAED8 \uC815\uB82C"],
  "\u6309\u9879\u76EE\u805A\u5408": ["Group by project", "\u4F9D\u5C08\u6848\u5206\u7D44", "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u5225", "\uD504\uB85C\uC81D\uD2B8\uBCC4 \uADF8\uB8F9\uD654"],
  "\u9ED8\u8BA4 \xB7 \u6240\u6709\u7F6E\u9876\u7EDF\u4E00\u6392\u5E8F": ["Default \xB7 One list for all pins", "\u9810\u8A2D \xB7 \u6240\u6709\u7F6E\u9802\u7D71\u4E00\u6392\u5E8F", "\u65E2\u5B9A \xB7 \u30D4\u30F3\u7559\u3081\u3092\u4E00\u62EC\u8868\u793A", "\uAE30\uBCF8 \xB7 \uBAA8\uB4E0 \uACE0\uC815 \uD56D\uBAA9\uC744 \uD55C \uBAA9\uB85D\uC5D0 \uD45C\uC2DC"],
  "\u672A\u5F52\u5C5E\u9879\u76EE": ["No project", "\u672A\u6B78\u5C6C\u5C08\u6848", "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u306A\u3057", "\uD504\uB85C\uC81D\uD2B8 \uC5C6\uC74C"],
  "\u5929\u84DD": ["Sky blue", "\u5929\u85CD", "\u30B9\u30AB\u30A4\u30D6\u30EB\u30FC", "\uD558\uB298\uC0C9"],
  "\u84DD\u7D2B": ["Periwinkle", "\u85CD\u7D2B", "\u30DA\u30EA\u30A6\u30A3\u30F3\u30AF\u30EB", "\uC5F0\uBCF4\uB77C"],
  "\u7D2B\u7F57\u5170": ["Violet", "\u7D2B\u7F85\u862D", "\u30D0\u30A4\u30AA\u30EC\u30C3\u30C8", "\uBCF4\uB77C"],
  "\u5170\u7D2B": ["Orchid", "\u862D\u7D2B", "\u30AA\u30FC\u30AD\u30C3\u30C9", "\uB09C\uCD08\uC0C9"],
  "\u73AB\u7C89": ["Rose pink", "\u73AB\u7C89", "\u30ED\u30FC\u30BA\u30D4\u30F3\u30AF", "\uB85C\uC988 \uD551\uD06C"],
  "\u73CA\u745A": ["Coral", "\u73CA\u745A", "\u30B3\u30FC\u30E9\u30EB", "\uC0B0\uD638\uC0C9"],
  "\u6A59": ["Orange", "\u6A59", "\u30AA\u30EC\u30F3\u30B8", "\uC8FC\uD669"],
  "\u91D1\u9EC4": ["Gold", "\u91D1\u9EC3", "\u30B4\u30FC\u30EB\u30C9", "\uAE08\uC0C9"],
  "\u67E0\u6AAC": ["Lemon", "\u6AB8\u6AAC", "\u30EC\u30E2\u30F3", "\uB808\uBAAC\uC0C9"],
  "\u9752\u67E0": ["Lime", "\u840A\u59C6", "\u30E9\u30A4\u30E0", "\uB77C\uC784"],
  "\u8349\u7EFF": ["Grass green", "\u8349\u7DA0", "\u8349\u8272", "\uD480\uC0C9"],
  "\u8584\u8377": ["Mint", "\u8584\u8377", "\u30DF\u30F3\u30C8", "\uBBFC\uD2B8"],
  "\u9752\u78A7": ["Turquoise", "\u9752\u78A7", "\u30BF\u30FC\u30B3\u30A4\u30BA", "\uCCAD\uB85D"],
  "\u51B0\u84DD": ["Ice blue", "\u51B0\u85CD", "\u30A2\u30A4\u30B9\u30D6\u30EB\u30FC", "\uC544\uC774\uC2A4 \uBE14\uB8E8"],
  "\u674F\u8272": ["Apricot", "\u674F\u8272", "\u30A2\u30D7\u30EA\u30B3\u30C3\u30C8", "\uC0B4\uAD6C\uC0C9"],
  "\u96FE\u84DD": ["Dusty blue", "\u9727\u85CD", "\u30C0\u30B9\u30C6\u30A3\u30D6\u30EB\u30FC", "\uADF8\uB808\uC774 \uBE14\uB8E8"],
  "\u4FA7\u680F\u5DF2\u5207\u6362": ["Sidebar changed", "\u5074\u6B04\u5DF2\u5207\u63DB", "\u30B5\u30A4\u30C9\u30D0\u30FC\u304C\u5207\u308A\u66FF\u308F\u308A\u307E\u3057\u305F", "\uC0AC\uC774\uB4DC\uBC14\uAC00 \uC804\uD658\uB418\uC5C8\uC2B5\uB2C8\uB2E4"],
  "Codex \u8D26\u6237\u5DF2\u5207\u6362\uFF0C\u8BF7\u91CD\u65B0\u9009\u62E9": ["Codex account changed. Select again.", "Codex \u5E33\u865F\u5DF2\u5207\u63DB\uFF0C\u8ACB\u91CD\u65B0\u9078\u64C7", "Codex \u30A2\u30AB\u30A6\u30F3\u30C8\u304C\u5207\u308A\u66FF\u308F\u308A\u307E\u3057\u305F\u3002\u9078\u3073\u76F4\u3057\u3066\u304F\u3060\u3055\u3044", "Codex \uACC4\uC815\uC774 \uBCC0\uACBD\uB418\uC5C8\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uC120\uD0DD\uD558\uC138\uC694."],
  "\u6761\u76EE\u5DF2\u79FB\u51FA\u6392\u884C\u699C\uFF0C\u8BF7\u5237\u65B0": ["Item is no longer available. Refresh and try again.", "\u9805\u76EE\u5DF2\u5931\u6548\uFF0C\u8ACB\u91CD\u65B0\u6574\u7406", "\u9805\u76EE\u304C\u898B\u3064\u304B\u308A\u307E\u305B\u3093\u3002\u66F4\u65B0\u3057\u3066\u304F\u3060\u3055\u3044", "\uD56D\uBAA9\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4. \uC0C8\uB85C \uACE0\uCE68\uD558\uC138\uC694."],
  "\u8BF7\u8F93\u5165\u516D\u4F4D\u5341\u516D\u8FDB\u5236\u989C\u8272": ["Enter a six-digit hex color", "\u8ACB\u8F38\u5165\u516D\u4F4D\u5341\u516D\u9032\u4F4D\u8272\u78BC", "6\u6841\u306E\u30AB\u30E9\u30FC\u30B3\u30FC\u30C9\u3092\u5165\u529B\u3057\u3066\u304F\u3060\u3055\u3044", "6\uC790\uB9AC 16\uC9C4\uC218 \uC0C9\uC0C1\uC744 \uC785\uB825\uD558\uC138\uC694"],
  "\u65E0\u6548\u7684\u9884\u8BBE\u8272\u683C": ["Invalid preset slot", "\u7121\u6548\u7684\u9810\u8A2D\u8272\u683C", "\u7121\u52B9\u306A\u30D7\u30EA\u30BB\u30C3\u30C8\u67A0\u3067\u3059", "\uC798\uBABB\uB41C \uD504\uB9AC\uC14B \uCE78\uC785\uB2C8\uB2E4"],
  "\u65E0\u6548\u7684\u989C\u8272\u6765\u6E90": ["Invalid color source", "\u7121\u6548\u7684\u984F\u8272\u4F86\u6E90", "\u7121\u52B9\u306A\u8272\u306E\u6307\u5B9A\u3067\u3059", "\uC798\uBABB\uB41C \uC0C9\uC0C1 \uC18C\uC2A4\uC785\uB2C8\uB2E4"],
  "\u65E0\u6548\u7684\u4FA7\u680F\u8BBE\u7F6E": ["Invalid sidebar setting", "\u7121\u6548\u7684\u5074\u6B04\u8A2D\u5B9A", "\u7121\u52B9\u306A\u30B5\u30A4\u30C9\u30D0\u30FC\u8A2D\u5B9A\u3067\u3059", "\uC798\uBABB\uB41C \uC0AC\uC774\uB4DC\uBC14 \uC124\uC815\uC785\uB2C8\uB2E4"],
  "\u65E0\u6CD5\u786E\u5B9A\u5F53\u524D Codex \u8D26\u6237\uFF0C\u5DF2\u505C\u6B62\u540C\u6B65\uFF0C\u907F\u514D\u6DF7\u5165\u5176\u4ED6\u8D26\u6237\u6570\u636E": ["Cannot identify the Codex account. Sync paused.", "\u7121\u6CD5\u78BA\u8A8D\u76EE\u524D\u7684 Codex \u5E33\u865F\uFF0C\u5DF2\u66AB\u505C\u540C\u6B65", "Codex \u30A2\u30AB\u30A6\u30F3\u30C8\u3092\u7279\u5B9A\u3067\u304D\u306A\u3044\u305F\u3081\u540C\u671F\u3092\u505C\u6B62\u3057\u307E\u3057\u305F", "Codex \uACC4\uC815\uC744 \uD655\uC778\uD560 \uC218 \uC5C6\uC5B4 \uB3D9\uAE30\uD654\uB97C \uC911\uC9C0\uD588\uC2B5\uB2C8\uB2E4"],
  "\u5F53\u524D Codex \u7F6E\u9876\u6570\u636E\u683C\u5F0F\u4E0D\u53D7\u652F\u6301": ["Unsupported Codex pin format", "\u4E0D\u652F\u63F4\u76EE\u524D\u7684 Codex \u7F6E\u9802\u8CC7\u6599\u683C\u5F0F", "Codex \u306E\u30D4\u30F3\u7559\u3081\u5F62\u5F0F\u306B\u5BFE\u5FDC\u3057\u3066\u3044\u307E\u305B\u3093", "\uC9C0\uC6D0\uD558\uC9C0 \uC54A\uB294 Codex \uACE0\uC815 \uB370\uC774\uD130 \uD615\uC2DD\uC785\uB2C8\uB2E4"],
  "\u4E0D\u652F\u6301\u7684\u504F\u597D\u7248\u672C": ["Unsupported preferences version", "\u4E0D\u652F\u63F4\u7684\u504F\u597D\u8A2D\u5B9A\u7248\u672C", "\u8A2D\u5B9A\u306E\u30D0\u30FC\u30B8\u30E7\u30F3\u306B\u5BFE\u5FDC\u3057\u3066\u3044\u307E\u305B\u3093", "\uC9C0\uC6D0\uD558\uC9C0 \uC54A\uB294 \uC124\uC815 \uBC84\uC804\uC785\uB2C8\uB2E4"],
  "\u65E0\u6548\u8D26\u6237\u6807\u8BC6": ["Invalid account ID", "\u7121\u6548\u7684\u5E33\u865F\u8B58\u5225\u78BC", "\u7121\u52B9\u306A\u30A2\u30AB\u30A6\u30F3\u30C8 ID \u3067\u3059", "\uC798\uBABB\uB41C \uACC4\uC815 ID\uC785\uB2C8\uB2E4"],
  "Prism \u9700\u8981\u542F\u7528\u5305\u5185 Node \u540E\u7AEF\u4EE5\u8BFB\u53D6\u9879\u76EE\u5F52\u5C5E\u548C\u4FDD\u5B58\u914D\u8272": ["Enable the Prism Node backend to read project membership and save colors.", "\u8ACB\u555F\u7528 Prism \u7684 Node \u5F8C\u7AEF\u4EE5\u8B80\u53D6\u5C08\u6848\u6B78\u5C6C\u4E26\u5132\u5B58\u914D\u8272", "\u30D7\u30ED\u30B8\u30A7\u30AF\u30C8\u60C5\u5831\u306E\u53D6\u5F97\u3068\u914D\u8272\u306E\u4FDD\u5B58\u306B\u306F Prism \u306E Node \u30D0\u30C3\u30AF\u30A8\u30F3\u30C9\u304C\u5FC5\u8981\u3067\u3059", "\uD504\uB85C\uC81D\uD2B8 \uC815\uBCF4 \uD655\uC778\uACFC \uC0C9\uC0C1 \uC800\uC7A5\uC744 \uC704\uD574 Prism Node \uBC31\uC5D4\uB4DC\uB97C \uD65C\uC131\uD654\uD558\uC138\uC694"]
};
var columns = ["en", "zh-TW", "ja", "ko"];
var language = resolveLanguage("auto", globalThis.navigator?.languages ?? []);
var bindings = /* @__PURE__ */ new WeakMap();
var known = (key) => Object.hasOwn(strings, key);
function setLanguage(value) {
  if (!value || value === language) return false;
  language = value;
  return true;
}
function t(key, n, suffix = "") {
  const template = known(key) && strings[key][columns.indexOf(language)] || key;
  return (n == null ? template : template.replace("{n}", String(n))) + suffix;
}
function paint(node, attr, spec) {
  const value = t(...spec);
  if (attr === "text") {
    if (node.firstChild?.nodeType !== 3) node.prepend(document.createTextNode(value));
    else if (node.firstChild.data !== value) node.firstChild.data = value;
  } else if (node.getAttribute(attr) !== value) node.setAttribute(attr, value);
}
function bind(node, key, attr = "text", n, suffix = "") {
  let fields = bindings.get(node);
  if (!fields) {
    fields = /* @__PURE__ */ new Map();
    bindings.set(node, fields);
    node.dataset.prismI18n = "";
  }
  const old = fields.get(attr);
  if (old && old[0] === key && Object.is(old[1], n) && old[2] === suffix) return;
  const spec = [key, n, suffix];
  fields.set(attr, spec);
  paint(node, attr, spec);
}
function translateTree(root) {
  root.lang = language;
  for (const node of [root, ...root.querySelectorAll("[data-prism-i18n]")]) {
    for (const [attr, spec] of bindings.get(node) ?? []) paint(node, attr, spec);
  }
}

// src/model.mjs
var PALETTE = [
  "#62A1FF",
  "#8C87FF",
  "#B47BFA",
  "#EF79E5",
  "#FF79A9",
  "#FF746F",
  "#FFA153",
  "#FFD059",
  "#E0EE69",
  "#A7E85D",
  "#69DA83",
  "#4FDCB4",
  "#44DDD9",
  "#56D4FA",
  "#F2B68B",
  "#A9C1E1"
];
var threadKey = (t2) => `${t2.kind || "codex"}:thread:${t2.hostId || "local"}:${t2.id}`;
var clientThreadKeyPrefix = "codex:thread:local:client-new-thread:";
var projectKey = (id) => `project:${id}`;
function threadColorSource(key, prefs, fallback = "default") {
  return prefs.colors[key] ? "custom" : prefs.threadColorModes?.[key] ?? fallback;
}
function colorFor(t2, prefs, fallback = "default") {
  const key = threadKey(t2);
  const source = threadColorSource(key, prefs, fallback);
  if (source === "custom") return prefs.colors[key];
  return source === "project" && t2.projectId ? prefs.colors[projectKey(t2.projectId)] ?? null : null;
}
function orderedThreads(threads, prefs) {
  if (!prefs.order.length) return [...threads];
  const indices = new Map(prefs.order.map((id, i) => [id, i]));
  return [...threads].sort((a, b) => (indices.get(threadKey(a)) ?? Infinity) - (indices.get(threadKey(b)) ?? Infinity));
}
function groupedThreads(threads, projects, prefs) {
  const ordered = orderedThreads(threads, prefs);
  if (prefs.mode === "all") return [{ id: "all", name: "\u5168\u90E8\u7F6E\u9876", threads: ordered }];
  if (prefs.mode === "project") {
    const byId = new Map(projects.map((p) => [p.id, p]));
    const buckets = /* @__PURE__ */ new Map();
    for (const t2 of ordered) {
      const id = t2.projectId || "none";
      if (!buckets.has(id)) buckets.set(id, { id, name: byId.get(id)?.name || t2.projectId || t("\u672A\u5F52\u5C5E\u9879\u76EE"), threads: [] });
      buckets.get(id).threads.push(t2);
    }
    return [...buckets.values()];
  }
  const groups = prefs.groups.map((g) => ({ ...g, threads: [] }));
  const ungrouped = { id: "ungrouped", name: "\u672A\u5206\u7EC4", threads: [] };
  for (const t2 of ordered) (groups.find((g) => g.id === prefs.assignments[threadKey(t2)]) || ungrouped).threads.push(t2);
  return [...groups, ...ungrouped.threads.length ? [ungrouped] : []];
}
function applyColorEdit(prefs, op) {
  if (op.value !== null && (typeof op.value !== "string" || !/^#[0-9a-f]{6}$/i.test(op.value))) {
    throw new Error("\u8BF7\u8F93\u5165\u516D\u4F4D\u5341\u516D\u8FDB\u5236\u989C\u8272");
  }
  const color = op.value?.toUpperCase();
  if (op.type === "preset-color") {
    if (!color || !Number.isInteger(op.slot) || op.slot < 0 || op.slot >= PALETTE.length) throw new Error("\u65E0\u6548\u7684\u9884\u8BBE\u8272\u683C");
    const palette = [...prefs.presetColors ?? PALETTE];
    palette[op.slot] = color;
    prefs.presetColors = palette;
    return;
  }
  const isProject = op.key.startsWith("project:");
  if (op.source !== void 0 && (isProject || color || !["default", "project"].includes(op.source))) throw new Error("\u65E0\u6548\u7684\u989C\u8272\u6765\u6E90");
  if (color) prefs.colors[op.key] = color;
  else delete prefs.colors[op.key];
  if (isProject) {
    if (typeof op.inherit === "boolean") prefs.inheritance[op.key.slice(8)] = op.inherit;
  } else if (op.source || prefs.threadColorModes?.[op.key]) {
    prefs.threadColorModes = { ...prefs.threadColorModes };
    if (op.source) prefs.threadColorModes[op.key] = op.source;
    else delete prefs.threadColorModes[op.key];
  }
  if (color) {
    prefs.recentColors = [color, ...(prefs.recentColors ?? []).filter((item) => item !== color)].slice(0, 6);
  }
}

// native/sidebar.mjs
function mountPrismSidebar({ mode, palette, colors = {}, projectIds = {}, threadProjects = {}, threadColorModes = {}, getClientBindings, layoutRows, projectColor, chatColor }) {
  const key = "__prismNativeSidebarV1";
  const sidebar = document.querySelector("[data-sidebar-navigation-root]");
  if (!sidebar) throw new Error("\u627E\u4E0D\u5230\u672C\u673A Codex \u4FA7\u680F\uFF0C\u672A\u5E94\u7528\u6837\u5F0F");
  if (!Array.isArray(palette) || palette.length !== 16 || !palette.every(isHex)) {
    throw new Error("Prism \u914D\u8272\u65E0\u6548");
  }
  const sectionAttribute = "data-app-action-sidebar-section-heading";
  const rowAttribute = "data-app-action-sidebar-thread-row";
  const threadAttribute = "data-app-action-sidebar-thread-id";
  const projectAttribute = "data-app-action-sidebar-project-id";
  const pinnedSection = '[data-app-action-sidebar-section][data-app-action-sidebar-section-heading="Pinned"]';
  const sidebarSection = "[data-app-action-sidebar-section]";
  const threadRow = `[${rowAttribute}][${threadAttribute}]`;
  const selectedRows = /* @__PURE__ */ new Set();
  const selectedProjects = /* @__PURE__ */ new Set();
  const chatRows = /* @__PURE__ */ new Set();
  let frame = null;
  function isHex(color) {
    return typeof color === "string" && /^#[0-9a-f]{6}$/i.test(color);
  }
  function setAccent(row, color) {
    const configured = isHex(color);
    if (configured ? row.style.getPropertyValue("--prism-native-color") === color && row.hasAttribute("data-prism-accent") : !row.hasAttribute("data-prism-accent") && !row.style.getPropertyValue("--prism-native-color")) return;
    row.toggleAttribute("data-prism-accent", configured);
    if (!configured) {
      row.style.removeProperty("--prism-native-color");
      row.style.removeProperty("--prism-native-ink");
      return;
    }
    row.style.setProperty("--prism-native-color", color);
    const channels = color.slice(1).match(/../g).map((byte) => parseInt(byte, 16) / 255).map((c) => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    const luma = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    row.style.setProperty("--prism-native-ink", luma > 0.179 ? "#000" : "#fff");
  }
  function clearRow(row) {
    row.removeAttribute("data-prism-native-rank");
    row.removeAttribute("data-prism-native-filtered");
    setAccent(row, null);
    row.style.removeProperty("--prism-native-fraction");
    selectedRows.delete(row);
  }
  function clearProject(row) {
    row.removeAttribute("data-prism-native-project");
    setAccent(row, null);
    selectedProjects.delete(row);
  }
  function clearChat(row) {
    row.removeAttribute("data-prism-chat");
    if (!selectedRows.has(row)) setAccent(row, null);
    chatRows.delete(row);
  }
  function ownRows(section, selector) {
    return section ? Array.from(section.querySelectorAll(selector)).filter(
      (row) => row.closest("[data-app-action-sidebar-section]") === section && (row.getClientRects().length > 0 || row.hasAttribute("data-prism-native-filtered"))
    ) : [];
  }
  function uniqueThreadRows(rows, bindings) {
    const seen = /* @__PURE__ */ new Set();
    const unique = [];
    for (const row of rows) {
      const thread = readThread(row, bindings);
      if (!thread.id) continue;
      const key = threadKey(thread);
      if (seen.has(key)) return [];
      seen.add(key);
      unique.push(row);
    }
    return unique;
  }
  function getSections() {
    const root = document.querySelector("[data-sidebar-navigation-root]");
    const pins = root?.querySelectorAll(pinnedSection);
    return {
      pins: pins?.length === 1 ? pins[0] : null,
      sections: Array.from(root?.querySelectorAll(sidebarSection) ?? [])
    };
  }
  function paint2() {
    const { pins, sections } = getSections();
    const bindings = getClientBindings?.();
    const pinRows = uniqueThreadRows(ownRows(pins, `${threadRow}[data-app-action-sidebar-thread-pinned="true"]`), bindings);
    const desiredRows = mode === "smoke" ? pinRows.slice(0, 1) : pinRows;
    const layout = layoutRows?.(pinRows, pins);
    for (const existing of selectedRows) if (!desiredRows.includes(existing)) clearRow(existing);
    for (const [index, row] of desiredRows.entries()) {
      if (layout?.pending.has(row)) {
        if (selectedRows.has(row)) clearRow(row);
        continue;
      }
      const thread = readThread(row, bindings);
      const preferenceKey = threadKey(thread);
      const projectId2 = threadProjects[preferenceKey] ?? null;
      const own = colors[preferenceKey];
      const inherited = projectId2 && threadColorModes[preferenceKey] === "project" && colors[`project:${projectId2}`];
      const entry = layout?.rows.get(row);
      const color = entry ? entry.color : own ?? inherited;
      const rank = entry?.rank ?? index + 1;
      const count = entry?.total ?? pinRows.length;
      row.toggleAttribute("data-prism-native-filtered", Boolean(entry?.hidden));
      const label = String(rank).padStart(2, "0");
      if (row.getAttribute("data-prism-native-rank") !== label) row.setAttribute("data-prism-native-rank", label);
      setAccent(row, color);
      row.style.setProperty("--prism-native-fraction", String(1 - (rank - 1) / Math.max(1, count - 1) * 0.45));
      selectedRows.add(row);
    }
    const expanded = sections.filter(section => section.getAttribute("data-app-action-sidebar-section-collapsed") !== "true");
    const projectRows = mode === "smoke" ? [] : expanded.flatMap(
      section => ownRows(section, `[data-app-action-sidebar-project-row][${projectAttribute}]`)
    );
    for (const row of selectedProjects) if (!projectRows.includes(row)) clearProject(row);
    for (const row of projectRows) {
      const raw = row.getAttribute(projectAttribute);
      const id = Object.hasOwn(projectIds, raw) ? projectIds[raw] : raw;
      const preferenceKey = `project:${id}`;
      row.toggleAttribute("data-prism-native-project", true);
      setAccent(row, projectColor ? projectColor(row) : colors[preferenceKey]);
      selectedProjects.add(row);
    }
    if (chatColor && mode !== "smoke") {
      const visible = new Set(expanded.flatMap(section => ownRows(section, threadRow)).filter((row) => {
        const thread = readThread(row, bindings);
        return !selectedRows.has(row) && thread.id && thread.kind === "codex" && thread.hostId === "local";
      }));
      for (const row of chatRows) if (!visible.has(row)) clearChat(row);
      for (const row of visible) {
        row.toggleAttribute("data-prism-chat", true);
        setAccent(row, chatColor(row));
        chatRows.add(row);
      }
    }
  }
  window[key]?.dispose();
  const style = document.createElement("style");
  style.dataset.packpierStyle = "prism";
  style.setAttribute("data-prism-native-styles", "");
  style.textContent = `
    [data-sidebar-navigation-root] [data-prism-native-filtered] {display:none !important}
    [data-sidebar-navigation-root] [data-prism-native-rank] {
      position:relative;
      padding-inline-start:39px !important;
    }
    [data-sidebar-navigation-root] [data-prism-native-rank]::before {
      content:attr(data-prism-native-rank);
      position:absolute; inset-inline-start:4px; top:50%;
      width:30px; text-align:end; transform:translateY(-50%); opacity:.72;
      font:inherit; font-size:.85em; font-variant-numeric:tabular-nums; pointer-events:none;
    }
    [data-sidebar-navigation-root] [data-prism-native-rank]::after {
      content:""; position:absolute; inset-inline-start:3px; top:50%; transform:translateY(-50%);
      width:10px; height:15px; opacity:.65; z-index:1; cursor:grab; touch-action:none; pointer-events:auto;
      background:radial-gradient(circle,currentColor 1px,transparent 1.2px) center / 5px 5px;
    }
    [data-sidebar-navigation-root] [data-prism-native-rank]:active::after {cursor:grabbing}
    [data-sidebar-navigation-root] [data-prism-native-rank] [data-thread-title] {
      box-sizing:border-box;
      padding-inline:7px;
    }
    [data-sidebar-navigation-root] [data-prism-native-rank] [data-thread-title-trigger] {
      padding-inline-end:24px;
    }
    /* Native row wrappers span the list, independent of indentation, status dots and hover actions. */
    [data-sidebar-navigation-root] :has(> :is([data-prism-native-rank],[data-prism-chat])[data-prism-accent]) {container-type:inline-size}
    [data-sidebar-navigation-root] :is([data-prism-native-rank],[data-prism-chat])[data-prism-accent] [data-thread-title] {
      display:inline-flex; align-items:center; align-self:center;
      box-sizing:border-box; padding-inline:7px; flex:0 0 auto; min-width:0;
      /* The first pin reserves 39px for rank/handle, .5rem of row padding and 5.5rem for actions. */
      width:max(0px,calc((100cqi - 39px - 6rem) * var(--prism-native-fraction, 1)));
      min-height:1.55em; border-radius:4px; overflow:hidden;
      background-color:var(--prism-native-color); color:var(--prism-native-ink);
    }
    :where([data-sidebar-navigation-root] [data-prism-native-project][data-prism-accent]) { position:relative }
    [data-sidebar-navigation-root] [data-prism-native-project][data-prism-accent]::before {
      content:""; position:absolute; inset-inline-start:0; inset-block:3px;
      width:3px; border-radius:2px; background:var(--prism-native-color); pointer-events:none;
    }
    [data-sidebar-navigation-root] [data-prism-native-project][data-prism-accent] [data-sidebar-project-kind] svg:first-child {
      color:var(--prism-native-color);
    }
  `;
  document.head.append(style);
  const observer = new MutationObserver(schedule);
  observer.observe(sidebar, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: [sectionAttribute, threadAttribute, projectAttribute, "data-app-action-sidebar-thread-kind",
      "data-app-action-sidebar-thread-host-id", "data-app-action-sidebar-thread-pinned", "data-app-action-sidebar-section-collapsed", "hidden"]
  });
  function schedule() {
    if (frame !== null) return;
    frame = requestAnimationFrame(() => {
      frame = null;
      paint2();
    });
  }
  function refreshNow() {
    if (frame !== null) cancelAnimationFrame(frame);
    frame = null;
    paint2();
  }
  function status() {
    const { pins } = getSections();
    return {
      mode,
      pinnedSection: Boolean(pins),
      pinnedRows: selectedRows.size,
      projectRows: selectedProjects.size,
      styleApplied: Array.from(selectedRows).every(
        (row) => getComputedStyle(row, "::before").position === "absolute" && getComputedStyle(row, "::before").content !== "none"
      ) && selectedRows.size > 0
    };
  }
  function dispose() {
    observer.disconnect();
    if (frame !== null) cancelAnimationFrame(frame);
    for (const row of selectedRows) clearRow(row);
    for (const row of selectedProjects) clearProject(row);
    for (const row of chatRows) clearChat(row);
    style.remove();
    delete window[key];
  }
  window[key] = { status, dispose, refresh: schedule, refreshNow };
  paint2();
  return status();
}

function readThread(row, clientBindings) {
  const attr = (name) => row.getAttribute("data-app-action-sidebar-thread-" + name);
  const rawId = attr("id") || "";
  const kind = attr("kind") || "local";
  const hostId = attr("host-id") || "local";
  const local = hostId === "local" && (kind === "local" || kind === "codex");
  const id = local ? rawId.replace(/^(?:codex:thread:)?local:/, "") : rawId;
  // Codex can retain its client ID in the DOM after the conversation has a server ID.
  const binding = (key) => Object.hasOwn(clientBindings, key) ? clientBindings[key] : undefined;
  const resolved = local && clientBindings ? binding(id) || binding(rawId) || id : id;
  return { id: resolved, kind: kind === "local" ? "codex" : kind, hostId };
}
function projectId(row, state) {
  if (row.hasAttribute("data-prism-group-project")) return row.dataset.prismGroupProject;
  const raw = row.getAttribute("data-app-action-sidebar-project-id") || row.closest("[data-app-action-sidebar-project-list-id]")?.getAttribute("data-app-action-sidebar-project-list-id");
  if (!raw) return null;
  const id = raw.replace(/^codex:project:/, "");
  return state.projectAliases?.[id] ?? id;
}
function chatTint(row, state) {
  const thread = readThread(row, state.clientBindings);
  const key = threadKey(thread);
  if (key.startsWith(clientThreadKeyPrefix)) return null;
  thread.projectId = state.threadProjects?.[key] ?? projectId(row, state);
  return colorFor(thread, state.preferences);
}
function projectTint(row, state) {
  const key = projectKey(projectId(row, state));
  return state.preferences.colors[key] ?? null;
}
function makeLayout(rows, state) {
  const catalog = new Map(state.threads.map((t2) => [threadKey(t2), t2]));
  const resolved = new Map();
  const pending = new Set();
  for (const row of rows) {
    const thread = readThread(row, state.clientBindings);
    const key = threadKey(thread);
    const known = catalog.get(key);
    const projectId = known?.projectId ?? state.threadProjects?.[key];
    if ((!known || known.pending) && !projectId) pending.add(row);
    else resolved.set(row, { ...(known ?? thread), projectId });
  }
  const visible = [...resolved.values()];
  const ranked = state.threads.filter(thread => !thread.pending || thread.projectId || state.threadProjects?.[threadKey(thread)]);
  const subset = visible.length < ranked.length && visible.every((t2, i) => t2.nativeIndex != null && (i === 0 || t2.nativeIndex > visible[i - 1].nativeIndex));
  const ordered = subset ? ranked : visible;
  const prefs = { ...state.preferences, order: [] };
  const groups = groupedThreads(visible, state.projects, prefs);
  const positions = new Map(ordered.map((thread, i) => [threadKey(thread), {
    rank: i + 1,
    total: ordered.length,
    color: colorFor(thread, prefs)
  }]));
  for (const group of groups) {
    for (const thread of group.threads) positions.get(threadKey(thread)).groupId = group.id;
  }
  return { groups, rows: new Map([...resolved].map(([row, thread]) => [row, positions.get(threadKey(thread))])), pending };
}

function el(tag, text) {
  const element = document.createElement(tag);
  if (text && known(text)) bind(element, text);
  else if (text) element.textContent = text;
  return element;
}
function button(label, action) {
  const item = el("button", label);
  item.type = "button";
  item.addEventListener("click", action);
  return item;
}
function icon(path) {
  const ns = "http://www.w3.org/2000/svg", svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 20 20");
  svg.setAttribute("aria-hidden", "true");
  const line = document.createElementNS(ns, "path");
  line.setAttribute("d", path);
  svg.append(line);
  return svg;
}

var names = ["\u5929\u84DD", "\u84DD\u7D2B", "\u7D2B\u7F57\u5170", "\u5170\u7D2B", "\u73AB\u7C89", "\u73CA\u745A", "\u6A59", "\u91D1\u9EC4", "\u67E0\u6AAC", "\u9752\u67E0", "\u8349\u7EFF", "\u8584\u8377", "\u9752\u78A7", "\u51B0\u84DD", "\u674F\u8272", "\u96FE\u84DD"];
function swatch(color, choose, label = color) {
  const item = button("", () => choose(color));
  item.className = "prism-swatch";
  item.dataset.color = color;
  item.title = label;
  item.setAttribute("aria-label", label);
  item.style.backgroundColor = color;
  return item;
}
function markSwatches(root, color) {
  for (const item of root.querySelectorAll("button[data-color]")) {
    const selected = String(item.dataset.color === color);
    if (item.getAttribute("aria-pressed") !== selected) item.setAttribute("aria-pressed", selected);
  }
}
function syncPresetGrid(grid, palette = PALETTE) {
  for (const [index, item] of Array.from(grid.children).entries()) {
    const color = palette[index];
    if (item.dataset.color === color) continue;
    const name = color === PALETTE[index] ? names[index] : "\u7B2C {n} \u683C";
    item.dataset.color = color;
    bind(item, name, "title", index + 1, " " + color);
    bind(item, name, "aria-label", index + 1, " " + color);
    item.style.backgroundColor = color;
  }
}
function presetGrid(choose, palette) {
  const grid = el("div");
  grid.className = "prism-swatches";
  grid.setAttribute("role", "group");
  bind(grid, "\u9884\u8BBE\u8272\u677F", "aria-label");
  PALETTE.forEach((_, index) => {
    const item = button("", () => choose(item.dataset.color, index));
    item.className = "prism-swatch";
    item.onkeydown = (event) => {
      const step = { ArrowRight: 1, ArrowLeft: -1, ArrowUp: -8, ArrowDown: 8 }[event.key];
      if (step) {
        event.preventDefault();
        grid.children[(index + step + 16) % 16].focus();
      }
    };
    grid.append(item);
  });
  syncPresetGrid(grid, palette);
  return grid;
}

var clamp = (n) => Math.min(1, Math.max(0, n));
function hsvFromHex(color, lastHue) {
  const [r, g, b] = color.slice(1).match(/../g).map((byte) => parseInt(byte, 16) / 255);
  const value = Math.max(r, g, b), delta = value - Math.min(r, g, b);
  let hue = lastHue;
  if (delta) {
    const sector = value === r ? (g - b) / delta : value === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
    hue = (sector * 60 + 360) % 360;
  }
  return { hue, saturation: value ? delta / value : 0, value };
}
function hexFromHSV({ hue, saturation, value }) {
  const c = value * saturation, x = c * (1 - Math.abs(hue / 60 % 2 - 1)), m = value - c;
  const rgb = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][Math.floor(hue / 60) % 6];
  return "#" + rgb.map((n) => Math.round((n + m) * 255).toString(16).padStart(2, "0")).join("").toUpperCase();
}
function createColorMixer({ initial, apply, place, slot }) {
  const root = el("div");
  root.className = slot === void 0 ? "prism-mixer" : "prism-mixer prism-slot-mixer";
  let color = initial.toUpperCase(), hsv = hsvFromHex(color, 0), sampler, disposed = false;
  const spectrum = el("div"), field = el("div"), hue = el("input");
  field.className = "prism-color-field";
  field.tabIndex = 0;
  field.setAttribute("role", "group");
  bind(field, "\u9971\u548C\u5EA6\u548C\u660E\u5EA6\uFF0C\u65B9\u5411\u952E\u8C03\u6574", "aria-label");
  field.append(el("i"));
  hue.className = "prism-hue";
  hue.type = "range";
  hue.min = "0";
  hue.max = "359";
  hue.step = "1";
  bind(hue, "\u8272\u76F8", "aria-label");
  spectrum.append(field, hue);
  const hexBox = el("label"), preview = el("i"), hex = el("input");
  hexBox.className = "prism-hex";
  hex.spellcheck = false;
  hex.autocomplete = "off";
  hex.maxLength = 7;
  bind(hex, "\u5341\u516D\u8FDB\u5236\u989C\u8272", "aria-label");
  hexBox.append(preview, hex, el("small", "HEX"));
  let useSystemPicker = !window.EyeDropper;
  const sampleLabel = el("span", useSystemPicker ? "\u7CFB\u7EDF\u9009\u8272" : "\u5C4F\u5E55\u53D6\u8272");
  const sample = button("", pickScreen);
  sample.append(sampleLabel);
  bind(sample, useSystemPicker ? "\u7CFB\u7EDF\u9009\u8272" : "\u5C4F\u5E55\u53D6\u8272", "title");
  sample.className = "prism-sample-screen";
  sample.prepend(icon("m12.5 7 3-3a1.8 1.8 0 0 1 2.5 2.5l-3 3M10 5.5l4.5 4.5M11 7l-7 7-.7 2.7 2.7-.7 7-7"));
  const native = el("input");
  native.type = "color";
  native.tabIndex = -1;
  native.className = "prism-system-color";
  bind(native, "\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668", "aria-label");
  const actions = el("div"), confirm = button("", () => apply(color));
  bind(confirm, slot === void 0 ? "\u5E94\u7528\u989C\u8272" : "\u4FDD\u5B58\u5230\u7B2C {n} \u683C", "text", slot + 1);
  actions.className = "prism-editor-actions";
  confirm.className = "prism-apply";
  actions.append(confirm);
  const status = el("div");
  status.className = "prism-color-status";
  status.setAttribute("role", "status");
  if (slot === void 0) root.append(spectrum, hexBox, sample, native, actions, status);
  else {
    const footer = el("div");
    footer.className = "prism-slot-footer";
    footer.append(hexBox, sample, confirm);
    root.append(spectrum, footer, native, status);
  }
  function render(keepInput = false) {
    confirm.disabled = false;
    hex.setAttribute("aria-invalid", "false");
    if (!keepInput) hex.value = color;
    root.style.setProperty("--prism-hue", "hsl(" + hsv.hue + " 100% 50%)");
    field.style.setProperty("--prism-x", hsv.saturation * 100 + "%");
    field.style.setProperty("--prism-y", (1 - hsv.value) * 100 + "%");
    hue.value = String(Math.min(359, Math.round(hsv.hue)));
    preview.style.backgroundColor = color;
    native.value = color;
    bind(status, "");
  }
  function setColor(value) {
    color = value.toUpperCase();
    hsv = hsvFromHex(color, hsv.hue);
    render();
  }
  function fromHSV() {
    color = hexFromHSV(hsv);
    render();
  }
  function atPointer(e) {
    const r = field.getBoundingClientRect();
    hsv.saturation = clamp((e.clientX - r.left) / r.width);
    hsv.value = 1 - clamp((e.clientY - r.top) / r.height);
    fromHSV();
  }
  field.onpointerdown = (e) => {
    if (e.button === 0) {
      field.setPointerCapture(e.pointerId);
      atPointer(e);
    }
  };
  field.onpointermove = (e) => {
    if (field.hasPointerCapture(e.pointerId)) atPointer(e);
  };
  field.onkeydown = (e) => {
    const step = e.shiftKey ? 0.1 : 0.01;
    switch (e.key) {
      case "ArrowLeft":
        hsv.saturation = clamp(hsv.saturation - step);
        break;
      case "ArrowRight":
        hsv.saturation = clamp(hsv.saturation + step);
        break;
      case "ArrowDown":
        hsv.value = clamp(hsv.value - step);
        break;
      case "ArrowUp":
        hsv.value = clamp(hsv.value + step);
        break;
      default:
        return;
    }
    e.preventDefault();
    e.stopPropagation();
    fromHSV();
  };
  hue.oninput = () => {
    hsv.hue = Number(hue.value);
    fromHSV();
  };
  hex.oninput = () => {
    const digits = hex.value.trim().replace(/^#/, "");
    if (!/^[0-9a-f]{6}$/i.test(digits)) {
      confirm.disabled = true;
      hex.setAttribute("aria-invalid", "true");
      bind(status, "\u8BF7\u8F93\u5165\u516D\u4F4D HEX \u8272\u503C");
      place();
      return;
    }
    color = "#" + digits.toUpperCase();
    hsv = hsvFromHex(color, hsv.hue);
    render(true);
  };
  native.onchange = () => setColor(native.value);
  async function pickScreen() {
    if (sampler) return;
    if (useSystemPicker) {
      native.click();
      return;
    }
    const request = new AbortController();
    sampler = request;
    try {
      const result = await new window.EyeDropper().open({ signal: request.signal });
      if (!disposed && !request.signal.aborted) setColor(result.sRGBHex);
    } catch (error) {
      if (!disposed && error.name !== "AbortError") {
        useSystemPicker = true;
        bind(sample, "\u6253\u5F00\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668", "title");
        bind(sampleLabel, "\u6253\u5F00\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668");
        bind(status, "\u6B64\u7A97\u53E3\u65E0\u6CD5\u76F4\u63A5\u53D6\u6837\uFF0C\u53EF\u6539\u7528\u7CFB\u7EDF\u989C\u8272\u9009\u62E9\u5668\u3002");
        place();
      }
    } finally {
      sampler = null;
    }
  }
  render();
  return {
    root,
    getColor: () => color,
    focus: () => field.focus({ preventScroll: true }),
    sampling: () => Boolean(sampler),
    dispose() {
      disposed = true;
      sampler?.abort();
      root.remove();
    }
  };
}

function createColorEditor({ initial, palette = PALETTE, apply, place, savePreset, report }) {
  const root = el("div");
  root.className = "prism-color-editor";
  const methods = el("div");
  methods.className = "prism-color-methods";
  methods.setAttribute("role", "group");
  bind(methods, "\u9009\u8272\u65B9\u5F0F", "aria-label");
  const mix = button("\u8C03\u8272\u677F", () => showPresets(false));
  const presets = button("\u9884\u8BBE\u8272\u677F", () => showPresets(true));
  methods.append(mix, presets);
  const mixer = createColorMixer({ initial, apply, place });
  const presetsView = el("div");
  presetsView.className = "prism-preset-view";
  let slot = Math.max(0, palette.indexOf(initial));
  let slotMixer, saving, disposed = false;
  const grid = presetGrid((value, index) => {
    if (!slotMixer) return apply(value);
    if (slot !== index) editSlot(index);
  }, palette);
  const chip = el("i"), slotLabel = el("span");
  const disclosure = button("", () => {
    if (slotMixer) collapse();
    else editSlot(slot);
  });
  disclosure.className = "prism-slot-toggle";
  disclosure.append(chip, slotLabel, el("span", "\u6362\u8272"), icon("m5 8 5 5 5-5"));
  presetsView.append(grid, disclosure);
  root.append(methods, mixer.root, presetsView);
  function paintSlot() {
    const number = slot + 1;
    chip.style.backgroundColor = palette[slot];
    bind(slotLabel, "\u7B2C {n} \u683C", "text", number);
    bind(disclosure, "\u6362\u8272\uFF0C\u7B2C {n} \u683C", "aria-label", number);
    disclosure.setAttribute("aria-expanded", String(Boolean(slotMixer)));
    Array.from(grid.children).forEach((item, i) => item.setAttribute("aria-pressed", String(i === slot)));
  }
  function collapse() {
    slotMixer?.dispose();
    slotMixer = null;
    paintSlot();
    if (root.isConnected) place();
  }
  function editSlot(index) {
    slotMixer?.dispose();
    slot = index;
    slotMixer = createColorMixer({ initial: palette[index], slot: index, apply: commitSlot, place });
    presetsView.append(slotMixer.root);
    paintSlot();
    place();
  }
  async function commitSlot(value) {
    const editor = slotMixer;
    if (!editor || saving === editor) return;
    saving = editor;
    try {
      await savePreset(slot, value);
      if (!disposed && slotMixer === editor && editor.getColor() === value) {
        collapse();
        disclosure.focus({ preventScroll: true });
      }
    } catch (error) {
      if (!disposed) report(error.message || String(error));
    } finally {
      if (saving === editor) saving = null;
    }
  }
  function showPresets(show) {
    if (show && !presetsView.hidden) return;
    if (!show && slotMixer) collapse();
    if (show) slot = Math.max(0, palette.indexOf(mixer.getColor()));
    presetsView.hidden = !show;
    mixer.root.hidden = show;
    mix.setAttribute("aria-pressed", String(!show));
    presets.setAttribute("aria-pressed", String(show));
    paintSlot();
    if (root.isConnected) place();
  }
  showPresets(false);
  return {
    root,
    focus: mixer.focus,
    sampling: () => mixer.sampling() || slotMixer?.sampling(),
    sync(next = PALETTE) {
      if (next.length === palette.length && next.every((hex, i) => hex === palette[i])) return;
      palette = next;
      syncPresetGrid(grid, palette);
      paintSlot();
    },
    dispose() {
      disposed = true;
      slotMixer?.dispose();
      mixer.dispose();
      root.remove();
    }
  };
}

function mountPicker({ panel, isProject, getKey, getPreferences, effectiveColor, save, report, clearNotice, place }) {
  const heading = panel.querySelector(".prism-pop-heading");
  const title = heading.querySelector("strong");
  const originalTitle = isProject ? "\u9879\u76EE\u4E3B\u9898\u8272" : "\u4F1A\u8BDD\u4E3B\u9898\u8272";
  const library = el("div");
  library.className = "prism-library";
  const grid = presetGrid((color) => apply(color), getPreferences().presetColors);
  const history = el("div");
  history.className = "prism-shelf";
  const recent = el("div");
  recent.className = "prism-chips";
  recent.dataset.shelf = "recent";
  recent.setAttribute("role", "group");
  bind(recent, "\u6700\u8FD1\u4F7F\u7528", "aria-label");
  const add = button("\uFF0B", openEditor);
  add.className = "prism-add-color";
  bind(add, "\u81EA\u9009\u989C\u8272", "title");
  bind(add, "\u81EA\u9009\u989C\u8272", "aria-label");
  history.append(el("span", "\u6700\u8FD1\u4F7F\u7528"), recent);
  const actions = el("div");
  actions.className = "prism-color-sources";
  const inherit = button("\u7EE7\u627F\u9879\u76EE\u8272", () => apply(null, "project"));
  const reset = button("\u6062\u590D\u9ED8\u8BA4\u8272", () => apply(null, isProject ? void 0 : "default"));
  if (!isProject) actions.append(inherit);
  actions.append(reset);
  const backButton = button("", back);
  backButton.append(icon("m12 4-6 6 6 6"));
  bind(backButton, "\u8FD4\u56DE\u8272\u677F", "aria-label");
  backButton.hidden = true;
  heading.prepend(backButton);
  library.append(grid, history, actions);
  panel.append(library);
  let editor, previousHistory;
  async function apply(value, source) {
    const key = getKey();
    if (key.startsWith(clientThreadKeyPrefix)) {
      report("\u4F1A\u8BDD\u540C\u6B65\u4E2D\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5");
      return;
    }
    clearNotice();
    if (editor) back();
    try {
      await save({ type: "color", key, value, source });
    } catch (error) {
      report(error.message || String(error));
    }
  }
  function back() {
    if (!editor) return false;
    editor.dispose();
    editor = null;
    backButton.hidden = true;
    library.hidden = false;
    bind(title, originalTitle);
    bind(panel, originalTitle, "aria-label");
    panel.scrollTop = 0;
    sync(getPreferences());
    place();
    add.focus({ preventScroll: true });
    return true;
  }
  function openEditor() {
    const prefs = getPreferences();
    editor = createColorEditor({
      initial: prefs.colors[getKey()] || effectiveColor() || prefs.recentColors[0] || "#38C9AE",
      palette: prefs.presetColors,
      apply,
      place,
      report,
      savePreset: (slot, value) => save({ type: "preset-color", slot, value })
    });
    library.hidden = true;
    bind(title, "\u81EA\u9009\u989C\u8272");
    bind(panel, "\u81EA\u9009\u989C\u8272", "aria-label");
    backButton.hidden = false;
    panel.append(editor.root);
    panel.scrollTop = 0;
    place();
    editor.focus();
  }
  function sync(prefs) {
    if (editor) {
      editor.sync(prefs.presetColors);
      return;
    }
    syncPresetGrid(grid, prefs.presetColors);
    const signature = prefs.recentColors.join(",");
    if (signature !== previousHistory) {
      previousHistory = signature;
      const focused = document.activeElement;
      const hadFocus = recent.contains(focused);
      recent.replaceChildren(...prefs.recentColors.map((color) => swatch(color, apply)), add);
      if (hadFocus) {
        const next = [...recent.children].find((b) => b.dataset.color === focused.dataset.color);
        (next || add).focus({ preventScroll: true });
      }
    }
    const key = getKey();
    markSwatches(library, prefs.colors[key]);
    const source = threadColorSource(key, prefs);
    reset.setAttribute("aria-pressed", String(isProject ? !prefs.colors[key] : source === "default"));
    if (!isProject) inherit.setAttribute("aria-pressed", String(source === "project"));
  }
  sync(getPreferences());
  return { sync, back, sampling: () => editor?.sampling(), dispose() {
    editor?.dispose();
  } };
}

function createPickerPosition(panel) {
  const edge = 5;
  let origin;
  function move(x, y) {
    const left = Math.max(edge, Math.min(x, innerWidth - panel.offsetWidth - edge));
    const top = Math.max(edge, Math.min(y, innerHeight - 112 - edge));
    origin = { x: left, y: top };
    panel.style.left = left + "px";
    panel.style.top = top + "px";
    panel.style.maxHeight = Math.max(0, innerHeight - top - edge) + "px";
  }
  function place(anchor, left) {
    if (origin) return move(origin.x, origin.y);
    const below = anchor.bottom + edge;
    const above = anchor.top - edge - panel.offsetHeight;
    move(left, below + panel.offsetHeight <= innerHeight - edge ? below : above);
  }
  function attach(heading) {
    let drag;
    bind(heading, "\u62D6\u52A8\u914D\u8272\u7A97\u53E3", "title");
    heading.onpointerdown = (event) => {
      if (event.button !== 0 || !event.isPrimary || event.target.closest("button")) return;
      const rect = panel.getBoundingClientRect();
      drag = { dx: event.clientX - rect.left, dy: event.clientY - rect.top, height: rect.height };
      heading.setPointerCapture(event.pointerId);
      heading.dataset.dragging = "";
      event.preventDefault();
    };
    heading.onpointermove = (event) => {
      if (!drag || !heading.hasPointerCapture(event.pointerId)) return;
      move(event.clientX - drag.dx, Math.min(event.clientY - drag.dy, innerHeight - drag.height - edge));
    };
    heading.onlostpointercapture = () => {
      drag = null;
      delete heading.dataset.dragging;
    };
  }
  return { place, attach, reset() {
    origin = null;
    panel.style.removeProperty("max-height");
  } };
}

var modes = [
  ["all", "\u5168\u90E8\u4E00\u8D77\u6392\u5E8F", "M3 4h14v4H3zM3 12h14v4H3z"],
  ["project", "\u6309\u9879\u76EE\u805A\u5408", "m2 7 8-5 8 5-8 5zM2 11l8 5 8-5"]
];
var paletteRows = "[data-prism-native-rank],[data-prism-native-project],[data-prism-chat],[data-prism-group-project]";
const paletteDotSize = 22;
const rowActionSelector = "button,[data-interactive-row-button],[role=button]";

function paletteInlineStart(row, bounds, rtl) {
  const inlineStart = (box) => rtl ? bounds.right - box.right : box.left - bounds.left;
  const inlineEnd = (box) => rtl ? bounds.right - box.left : box.right - bounds.left;
  const title = row.querySelector("[data-thread-title],.prism-group-toggle span") ?? row.querySelector("[data-thread-title-trigger]");
  const titleBox = title?.getBoundingClientRect();
  const range = document.createRange();
  const walker = document.createTreeWalker(title ?? row, NodeFilter.SHOW_TEXT);
  let textStart = Infinity, textEnd = 0;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const parent = node.parentElement;
    const control = parent.closest(rowActionSelector);
    if (!node.data.trim() || parent.closest(".sr-only,.prism-dot") || (!title && control && control !== row)) continue;
    range.selectNodeContents(node);
    const box = range.getBoundingClientRect();
    if (!box.width || !box.height || getComputedStyle(parent).visibility !== "visible") continue;
    textStart = Math.min(textStart, inlineStart(box));
    textEnd = Math.max(textEnd, inlineEnd(box));
  }
  if (title && getComputedStyle(title).overflowX !== "visible") textEnd = Math.min(textEnd, inlineEnd(titleBox));
  const titleStart = Math.max(0, titleBox ? inlineStart(titleBox) : Number.isFinite(textStart) ? textStart : bounds.width / 2);
  let actionStart = Infinity;
  for (const button of row.querySelectorAll(rowActionSelector)) {
    // Codex uses this same marker on the title button. It is not a trailing action.
    if (button.closest(".prism-dot,.sr-only,[hidden]") || (title && (button.contains(title) || title.contains(button)))) continue;
    const box = button.getBoundingClientRect();
    const start = inlineStart(box);
    if (!box.width || !box.height || start < titleStart - 1 || inlineEnd(box) > bounds.width + 1 ||
        box.bottom <= bounds.top || box.top >= bounds.bottom || getComputedStyle(button).visibility !== "visible") continue;
    actionStart = Math.min(actionStart, start);
  }
  const limit = Math.min(actionStart, bounds.width);
  const gap = Number.isFinite(actionStart) ? 6 : 30;
  const start = Math.max(0, Math.floor(limit - gap - paletteDotSize));
  return bounds.height >= paletteDotSize && start >= textEnd && start + paletteDotSize + gap <= limit ? start : null;
}

function createControls({ root, getState, save, signal }) {
  const toolbar = el("div");
  toolbar.className = "prism-tools";
  const modeButton = button("", () => {
    if (anchor === modeButton) close(true);
    else openModes();
  });
  bind(modeButton, "\u6392\u884C\u699C\u89C6\u56FE", "aria-label");
  modeButton.setAttribute("aria-haspopup", "menu");
  modeButton.setAttribute("aria-expanded", "false");
  const modeName = el("span");
  modeButton.append(modeName, icon("m5 8 5 5 5-5"));
  toolbar.append(modeButton);
  const paletteButton = button("", (e) => {
    e.stopPropagation();
    if (anchor === paletteButton) close(true);
    else openPicker();
  });
  paletteButton.className = "prism-dot";
  bind(paletteButton, "\u8BBE\u7F6E\u4E3B\u9898\u8272", "title");
  bind(paletteButton, "\u8BBE\u7F6E\u4E3B\u9898\u8272", "aria-label");
  paletteButton.setAttribute("aria-haspopup", "dialog");
  paletteButton.onpointerdown = (e) => e.stopPropagation();
  paletteButton.ontouchstart = (e) => e.stopPropagation();
  const panel = el("div");
  panel.className = "prism-pop";
  panel.tabIndex = -1;
  const pickerPosition = createPickerPosition(panel);
  const notice = el("div");
  notice.className = "prism-error";
  notice.setAttribute("role", "status");
  let anchor, panelTarget, activeRow, messageTimer, picker;
  const rowResize = new ResizeObserver(place);
  root.append(paletteButton, panel, notice);
  panel.hidden = paletteButton.hidden = notice.hidden = true;
  function clearNotice() {
    clearTimeout(messageTimer);
    notice.hidden = true;
  }
  function report(message) {
    bind(notice, message);
    notice.hidden = false;
    clearTimeout(messageTimer);
    messageTimer = setTimeout(() => {
      notice.hidden = true;
    }, 4500);
  }
  function close(focus = false) {
    picker?.dispose();
    picker = null;
    const previous = anchor;
    anchor = panelTarget = null;
    panel.hidden = true;
    pickerPosition.reset();
    if (panel.childElementCount) panel.replaceChildren();
    previous?.setAttribute("aria-expanded", "false");
    if (focus && previous?.isConnected) previous.focus({ preventScroll: true });
  }
  function place() {
    if (activeRow?.isConnected && activeRow.getClientRects().length) {
      const bounds = activeRow.getBoundingClientRect();
      const style = getComputedStyle(activeRow);
      const rtl = style.direction === "rtl";
      const start = paletteInlineStart(activeRow, bounds, rtl);
      paletteButton.hidden = start === null;
      if (start !== null) {
        const nested = paletteButton.parentNode === activeRow;
        const viewportStart = rtl ? document.documentElement.clientWidth - bounds.right : bounds.left;
        const inlineOrigin = nested ? -parseFloat(style.borderInlineStartWidth) : viewportStart;
        const blockOrigin = nested ? -parseFloat(style.borderTopWidth) : bounds.top;
        paletteButton.style.direction = style.direction;
        paletteButton.style.insetInlineStart = (inlineOrigin + start) + "px";
        paletteButton.style.top = (blockOrigin + (bounds.height - paletteDotSize) / 2) + "px";
        paletteButton.style.setProperty("--prism-swatch", activeRow.style.getPropertyValue("--prism-native-color") || activeRow.style.getPropertyValue("--prism-project-color") || "transparent");
      }
    } else if (!paletteButton.hidden) paletteButton.hidden = true;
    if (panel.hidden) return;
    const reference = anchor === paletteButton && paletteButton.hidden ? panelTarget : anchor;
    if (!reference?.isConnected || !reference.getClientRects().length || panelTarget && !panelTarget.getClientRects().length) return close();
    const r = reference.getBoundingClientRect();
    const sidebar = (panelTarget || anchor).closest("[data-sidebar-navigation-root]")?.getBoundingClientRect();
    const left = sidebar && sidebar.width >= panel.offsetWidth + 12 ? sidebar.left + 6 : 6;
    const right = sidebar && sidebar.width >= panel.offsetWidth + 12 ? sidebar.right - 6 : innerWidth - 6;
    const x = Math.max(left, Math.min(right, r.right) - panel.offsetWidth);
    if (panel.dataset.view === "color") return pickerPosition.place(r, x);
    panel.style.left = x + "px";
    const below = r.bottom + 5;
    const top = below + panel.offsetHeight <= innerHeight - 5 ? below : r.top - panel.offsetHeight - 5;
    panel.style.top = Math.max(5, top) + "px";
  }
  function show(target, title, type, row = null) {
    close();
    anchor = target;
    panelTarget = row;
    panel.dataset.view = type;
    panel.setAttribute("role", type === "mode" ? "menu" : "dialog");
    bind(panel, title, "aria-label");
    anchor.setAttribute("aria-expanded", "true");
    const heading = el("div");
    heading.className = "prism-pop-heading";
    heading.append(el("strong", title));
    if (type !== "mode") {
      pickerPosition.attach(heading);
      const dismiss = button("", () => close(true));
      bind(dismiss, "\u5173\u95ED", "aria-label");
      dismiss.append(icon("m5 5 10 10M15 5 5 15"));
      heading.append(dismiss);
    }
    panel.append(heading);
    panel.hidden = false;
  }
  function finishPanel(initial) {
    place();
    (initial || panel).focus({ preventScroll: true });
  }
  async function submit(operation) {
    close(true);
    try {
      await save(operation);
    } catch (error) {
      report(error.message || String(error));
    }
  }
  function openModes() {
    show(modeButton, "\u7F6E\u9876\u5C55\u793A\u65B9\u5F0F", "mode");
    const current = getState().preferences.mode;
    let checked;
    for (const [id, name, path] of modes) {
      const item = button("", () => submit({ type: "mode", value: id }));
      item.setAttribute("role", "menuitemradio");
      bind(item, name, "aria-label");
      item.setAttribute("aria-checked", String(current === id));
      const label = el("span", name);
      if (id === "all") label.append(el("small", "\u9ED8\u8BA4 \xB7 \u6240\u6709\u7F6E\u9876\u7EDF\u4E00\u6392\u5E8F"));
      item.append(icon(path), label);
      if (current === id) {
        checked = item;
        item.append(icon("m3 11 4 4L17 5"));
      }
      panel.append(item);
    }
    finishPanel(checked);
  }
  function openPicker() {
    const row = activeRow;
    if (!row?.isConnected || !getState()) return;
    const isProject = row.matches("[data-prism-native-project],[data-prism-group-project]");
    const getKey = () => {
      const state = getState();
      return isProject ? projectKey(projectId(row, state)) : threadKey(readThread(row, state.clientBindings));
    };
    show(paletteButton, isProject ? "\u9879\u76EE\u4E3B\u9898\u8272" : "\u4F1A\u8BDD\u4E3B\u9898\u8272", "color", row);
    picker = mountPicker({
      panel,
      isProject,
      getKey,
      getPreferences: () => getState().preferences,
      effectiveColor: () => row.style.getPropertyValue("--prism-native-color"),
      save,
      report,
      clearNotice,
      place
    });
    finishPanel(panel.querySelector("[aria-pressed=true]") || panel.querySelector(".prism-swatches button"));
  }
  function updateToolbar(section, mode) {
    if (!section || section.getAttribute("data-app-action-sidebar-section-collapsed") === "true") {
      toolbar.remove();
    } else {
      const toggle = section.querySelector("[data-app-action-sidebar-section-toggle],h2");
      if (toggle && toggle.nextElementSibling !== toolbar) toggle.after(toolbar);
      else if (!toggle && toolbar.parentElement !== section) section.prepend(toolbar);
      const label = modes.find(([id]) => id === mode)?.[1] || modes[0][1];
      bind(modeName, label);
    }
    place();
  }
  function identify(event) {
    if (!(event.target instanceof Element) || panel.contains(event.target) || paletteButton.contains(event.target) || !panel.hidden) return;
    const row = event.target.closest(paletteRows);
    if (activeRow !== row) {
      rowResize.disconnect();
      activeRow = row;
      const parent = row && !row.matches("button,a") ? row : root;
      if (paletteButton.parentNode !== parent) parent.append(paletteButton);
      if (row) rowResize.observe(row);
    }
    place();
  }
  document.addEventListener("pointerover", identify, { signal });
  document.addEventListener("focusin", identify, { signal });
  document.addEventListener("pointerdown", (e) => {
    if (!panel.hidden && !panel.contains(e.target) && !anchor?.contains(e.target)) close();
  }, { signal, capture: true });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !panel.hidden) {
      if (picker?.sampling()) return;
      e.preventDefault();
      e.stopPropagation();
      if (!picker?.back()) close(true);
    } else if (panel.contains(e.target) && panel.dataset.view === "mode" && ["ArrowUp", "ArrowDown", "Home", "End"].includes(e.key)) {
      e.preventDefault();
      e.stopPropagation();
      const options = [...panel.querySelectorAll("button")];
      const i = options.indexOf(e.target);
      const next = e.key === "Home" ? 0 : e.key === "End" ? options.length - 1 : (i + (e.key === "ArrowUp" ? -1 : 1) + options.length) % options.length;
      options[next].focus();
    } else if (e.altKey && e.key === "Enter" && e.target.closest?.(paletteRows)) {
      e.preventDefault();
      e.stopPropagation();
      close();
      identify(e);
      openPicker();
    }
  }, { signal, capture: true });
  window.addEventListener("scroll", (e) => {
    if (!panel.contains(e.target)) place();
  }, { signal, capture: true });
  window.addEventListener("resize", place, { signal });
  function translate() {
    for (const node of [root, toolbar, paletteButton]) translateTree(node);
  }
  translate();
  return {
    updateToolbar,
    report,
    translate,
    syncPalette(prefs) {
      picker?.sync(prefs);
    },
    reset() {
      close();
      rowResize.disconnect();
      toolbar.remove();
      activeRow = null;
      paletteButton.hidden = true;
      root.append(paletteButton);
    },
    dispose() {
      close();
      rowResize.disconnect();
      clearTimeout(messageTimer);
      toolbar.remove();
      paletteButton.remove();
      panel.remove();
      notice.remove();
    }
  };
}

function createGroupView(refresh) {
  let list, storageKey, collapsed = /* @__PURE__ */ new Set();
  const headers = /* @__PURE__ */ new Map();
  const items = /* @__PURE__ */ new Set();
  let marker, pointerY;
  const markerSelector = ":scope > [role=presentation][aria-hidden=true].h-0";
  function clearMarker() {
    marker?.removeAttribute("data-prism-drop-order");
    marker?.style.removeProperty("--prism-drop-order");
    marker = null;
  }
  function placeMarker() {
    if (!marker?.isConnected) return;
    const edges = [];
    for (const before of [true, false]) {
      const sibling = before ? "nextElementSibling" : "previousElementSibling";
      let item = marker[sibling];
      while (item && !items.has(item)) item = item[sibling];
      if (!item || item.hasAttribute("data-prism-folded")) continue;
      const rect = item.getBoundingClientRect();
      edges.push({
        order: Number(item.style.getPropertyValue("--prism-order")) + (before ? -1 : 1),
        y: before ? rect.top : rect.bottom
      });
    }
    if (!edges.length) {
      marker.removeAttribute("data-prism-drop-order");
      return;
    }
    const edge = pointerY == null ? edges[0] : edges.reduce((nearest, e) => Math.abs(e.y - pointerY) < Math.abs(nearest.y - pointerY) ? e : nearest);
    marker.style.setProperty("--prism-drop-order", String(edge.order));
    marker.setAttribute("data-prism-drop-order", "");
  }
  function trackPointer(event) {
    if (event.type === "pointermove" && !event.buttons) return;
    pointerY = event.clientY;
    if (marker) placeMarker();
  }
  function clearPointer() {
    pointerY = null;
  }
  function release(item) {
    item.removeAttribute("data-prism-item");
    item.removeAttribute("data-prism-folded");
    item.style.removeProperty("--prism-order");
    items.delete(item);
  }
  function leaveNative(rows) {
    for (const row of rows) {
      const item = row.closest("[role=listitem]");
      if (items.has(item)) release(item);
    }
  }
  function clear() {
    for (const item of items) release(item);
    for (const header of headers.values()) header.remove();
    headers.clear();
    if (list) {
      document.removeEventListener("pointermove", trackPointer, true);
      document.removeEventListener("dragover", trackPointer, true);
      document.removeEventListener("pointerup", clearPointer, true);
      document.removeEventListener("pointercancel", clearPointer, true);
      document.removeEventListener("keydown", clearPointer, true);
      clearMarker();
      clearPointer();
    }
    list?.removeAttribute("data-prism-group-list");
    list = null;
  }
  function headerFor(id) {
    if (headers.has(id)) return headers.get(id);
    const header = document.createElement("div");
    header.className = "prism-group";
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "prism-group-toggle";
    const title = document.createElement("span");
    const count = document.createElement("small");
    toggle.append(title, count);
    toggle.onclick = () => {
      if (collapsed.has(id)) collapsed.delete(id);
      else collapsed.add(id);
      try {
        sessionStorage.setItem(storageKey, JSON.stringify([...collapsed]));
      } catch {
      }
      refresh();
    };
    header.append(toggle);
    headers.set(id, header);
    list.append(header);
    return header;
  }
  function render(section, view, state) {
    if (!section || !view.rows.size || state.preferences.mode === "all" || section.getAttribute("data-app-action-sidebar-section-collapsed") === "true") {
      clear();
      return;
    }
    const first = view.rows.keys().next().value;
    const next = first?.closest("[role=listitem]")?.parentElement || section.querySelector("[role=list]");
    if (!next || !section.contains(next)) {
      clear();
      return;
    }
    const key = "ct-prism:fold:" + JSON.stringify([state.account, state.preferences.mode]);
    if (list !== next || storageKey !== key) {
      clear();
      list = next;
      storageKey = key;
      document.addEventListener("pointermove", trackPointer, { capture: true, passive: true });
      document.addEventListener("dragover", trackPointer, { capture: true, passive: true });
      document.addEventListener("pointerup", clearPointer, true);
      document.addEventListener("pointercancel", clearPointer, true);
      document.addEventListener("keydown", clearPointer, true);
      try {
        collapsed = new Set(JSON.parse(sessionStorage.getItem(key) || "[]"));
      } catch {
        collapsed = /* @__PURE__ */ new Set();
      }
    }
    list.setAttribute("data-prism-group-list", "");
    const buckets = new Map(view.groups.map((g) => [g.id, []]));
    const keep = /* @__PURE__ */ new Set();
    for (const [row, entry] of view.rows) {
      const item = row.closest("[role=listitem]");
      if (item?.parentElement !== list || !buckets.has(entry.groupId)) continue;
      buckets.get(entry.groupId).push([item, entry]);
      keep.add(item);
    }
    for (const item of items) if (!keep.has(item)) release(item);
    for (const [id, header] of headers) if (!buckets.get(id)?.length) {
      header.remove();
      headers.delete(id);
    }
    let order = 0;
    for (const group of view.groups) {
      const members = buckets.get(group.id);
      if (!members.length) continue;
      const header = headerFor(group.id);
      const isProject = state.projects.some((project) => project.id === group.id);
      if (isProject) header.dataset.prismGroupProject = group.id;
      else delete header.dataset.prismGroupProject;
      const color = state.preferences.colors[projectKey(group.id)];
      header.toggleAttribute("data-prism-project-accent", !!color);
      if (color) header.style.setProperty("--prism-project-color", color);
      else header.style.removeProperty("--prism-project-color");
      const toggle = header.firstElementChild;
      if (header.parentNode !== list) list.append(header);
      header.style.order = String(3 * order++);
      toggle.setAttribute("aria-expanded", String(!collapsed.has(group.id)));
      const name = state.preferences.mode === "project" || isProject ? group.name : t("\u672A\u5F52\u5C5E\u9879\u76EE");
      if (toggle.children[0].textContent !== name) toggle.children[0].textContent = name;
      const count = String(members.length);
      if (toggle.children[1].textContent !== count) toggle.children[1].textContent = count;
      for (const [item, entry] of members) {
        entry.hidden = collapsed.has(group.id);
        item.setAttribute("data-prism-item", "");
        item.toggleAttribute("data-prism-folded", entry.hidden);
        item.style.setProperty("--prism-order", String(3 * order++));
        items.add(item);
      }
    }
    const nextMarker = list.querySelector(markerSelector);
    if (marker !== nextMarker) {
      clearMarker();
      marker = nextMarker;
    }
    placeMarker();
  }
  return { render, clear, leaveNative };
}

var style_default = `.prism-tools,.prism-pop,.prism-dot,.prism-error,.prism-group {
  font:inherit; font-size:12px; line-height:1.4; color:var(--color-text-primary,CanvasText);
}
.prism-tools svg,.prism-pop svg {
  width:16px;height:16px;flex:none;fill:none;stroke:currentColor;stroke-width:1.5;stroke-linejoin:round;stroke-linecap:round;
}
.prism-tools {display:inline-flex;align-items:center;flex:none;margin-inline:4px}
.prism-tools button,.prism-pop button,.prism-group button,.prism-dot {
  font:inherit;color:inherit;cursor:pointer;background:transparent;border:0;box-sizing:border-box;
}
.prism-tools button {display:flex;align-items:center;gap:4px;padding:2px 5px;border-radius:5px;color:var(--color-text-tertiary,inherit)}
.prism-tools svg {width:12px;height:12px}
.prism-tools button:hover,.prism-pop button:hover,.prism-group button:hover,.prism-dot:hover {
  background:var(--color-background-primary-ghost-hover,color-mix(in srgb,currentColor 8%,transparent));
}
[data-prism-group-list] {display:flex;flex-direction:column;reading-flow:flex-visual}
[data-prism-item] {order:var(--prism-order)}
[data-prism-folded] {display:none!important}
.prism-group {display:flex;align-items:center;gap:4px;margin:5px 0 1px;min-width:0}
.prism-group-toggle {display:flex;align-items:center;gap:7px;flex:1;min-width:0;text-align:start;border-radius:5px;padding:4px 6px;font-weight:500!important}
.prism-group-toggle::before {content:'';width:6px;height:6px;flex:none;border:solid currentColor;border-width:0 1.25px 1.25px 0;transform:rotate(-45deg)}
.prism-group-toggle[aria-expanded=true]::before {transform:translateY(-2px) rotate(45deg)}
.prism-group-toggle span {overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.prism-group-toggle small {font-size:11px;opacity:.6;font-variant-numeric:tabular-nums}
.prism-group[data-prism-project-accent] {box-shadow:inset 3px 0 var(--prism-project-color);border-radius:3px;padding-inline-start:3px}
.prism-group[data-prism-project-accent] .prism-group-toggle::before {border-color:var(--prism-project-color)}
[data-prism-group-list]>[role=presentation][aria-hidden=true].h-0 {visibility:hidden}
[data-prism-group-list]>[data-prism-drop-order] {order:var(--prism-drop-order);visibility:visible!important}
.prism-dot,.prism-pop,.prism-error {position:fixed;z-index:2147482600;pointer-events:auto}
[data-prism-native-project],[data-prism-chat],[data-prism-group-project] {position:relative}
:is([data-prism-native-rank],[data-prism-native-project],[data-prism-chat],[data-prism-group-project])>.prism-dot {position:absolute;z-index:3}
button.prism-dot {display:grid;place-items:center;width:${paletteDotSize}px;height:${paletteDotSize}px;border-radius:5px;padding:0;color:var(--color-text-secondary,CanvasText)}
.prism-dot::before {content:'';width:11px;height:11px;box-sizing:border-box;border-radius:3px;border:1.25px solid currentColor;background:var(--prism-swatch,transparent)}
.prism-dot[style*="--prism-swatch: transparent"]::before {background:linear-gradient(135deg,transparent 0 50%,currentColor 50%)}
.prism-pop,.prism-error {
  color:var(--color-text-primary,CanvasText);background:var(--color-surface-elevated-secondary,Canvas);
  border:1px solid var(--color-border-default,color-mix(in srgb,currentColor 18%,transparent));
  box-shadow:0 5px 18px rgb(0 0 0 / .18);border-radius:var(--popover-radius,10px);padding:8px;
}
.prism-pop {box-sizing:border-box;display:grid;gap:3px;width:216px;max-width:calc(100vw - 12px);max-height:calc(100vh - 10px);overflow:auto}
.prism-pop-heading {display:flex;align-items:center;justify-content:space-between;padding:2px 4px 5px}
.prism-pop-heading strong {font-size:12px;font-weight:550}
.prism-pop-heading button {display:grid;place-items:center;width:20px;height:20px;padding:2px}
.prism-pop-heading svg {width:12px;height:12px}
.prism-pop button {border-radius:5px;text-align:start;padding:5px 6px}
.prism-pop [role^=menuitem] {display:flex;align-items:center;gap:9px;padding:7px 8px;min-height:30px}
.prism-pop [role^=menuitem] span {flex:1}
.prism-pop small {display:block;opacity:.65;font-size:11px}
.prism-pop [aria-checked=true] {background:var(--color-background-info-surface,color-mix(in srgb,Highlight 15%,transparent))}
.prism-swatches {display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:5px;padding:1px 4px 5px}
.prism-swatches button {display:grid;place-items:center;width:100%;aspect-ratio:1;padding:0;border-radius:5px;color:#141414}
.prism-swatches button[aria-pressed=true]::after {content:'';width:5px;height:9px;border:solid currentColor;border-width:0 2px 2px 0;transform:translateY(-1px) rotate(45deg)}
.prism-color-sources {display:flex;gap:4px;flex-wrap:wrap;position:sticky;bottom:0;background:var(--color-surface-elevated-secondary,Canvas);z-index:1}
.prism-color-sources button {font-size:11px;color:var(--color-text-secondary,inherit)}
.prism-color-sources [aria-pressed=true] {background:var(--color-background-primary-ghost-hover,color-mix(in srgb,currentColor 10%,transparent))}
.prism-tools :focus-visible,.prism-pop :focus-visible,.prism-group :focus-visible,.prism-dot:focus-visible {outline:2px solid var(--color-text-accent,Highlight);outline-offset:1px}
.prism-error {bottom:16px;left:16px;max-width:320px}
.prism-portal [hidden],.prism-dot[hidden] {display:none!important}

/* The shared editor is mounted only while the + view is open. */
.prism-pop[data-view=color]{width:296px;padding:12px;overscroll-behavior:contain}
.prism-pop[data-view=color] .prism-pop-heading{position:sticky;top:0;z-index:1;background:inherit;gap:6px;padding:0 0 9px;cursor:grab;user-select:none;touch-action:none}
.prism-pop[data-view=color] .prism-pop-heading[data-dragging]{cursor:grabbing}
.prism-pop-heading strong{flex:1}
.prism-library,.prism-color-editor{display:grid;min-width:0}
.prism-library{gap:6px}
.prism-shelf{border-top:1px solid var(--color-border-subtle,GrayText);padding:9px 4px 2px;display:grid;grid-template-columns:56px minmax(0,1fr);gap:5px;align-items:start}
.prism-shelf>span{font-size:12px;line-height:21px;color:var(--color-text-secondary,inherit)}
.prism-chips{display:flex;flex-wrap:wrap;gap:5px;align-items:center;min-height:21px}
.prism-chips .prism-swatch,.prism-chips .prism-add-color{display:grid;place-items:center;width:21px;height:21px;padding:0}
.prism-chips .prism-add-color{border:1px dashed var(--color-text-tertiary,GrayText);font-size:15px;line-height:1}
.prism-chips .prism-swatch[aria-pressed=true]::after{content:'';height:7px;width:4px;border:solid #111;border-width:0 2px 2px 0;transform:translateY(-1px) rotate(45deg);filter:drop-shadow(0 0 1px white)}
.prism-color-editor,.prism-mixer,.prism-preset-view{display:grid;gap:8px;min-width:0}
.prism-preset-view{gap:6px}
.prism-pop .prism-slot-toggle{display:flex;align-items:center;gap:7px;width:100%;padding:7px 4px 1px;border-top:1px solid var(--color-border-subtle,color-mix(in srgb,currentColor 16%,transparent));border-radius:0;min-height:27px}
.prism-slot-toggle i{width:13px;height:13px;flex:none;border-radius:3px;box-shadow:inset 0 0 0 1px rgb(128 128 128 / .25)}
.prism-slot-toggle span:nth-child(2){flex:1}
.prism-slot-toggle span:last-of-type,.prism-slot-toggle svg{color:var(--color-text-secondary,inherit)}
.prism-slot-toggle svg{width:12px;height:12px}
.prism-slot-toggle[aria-expanded=true] svg{transform:rotate(180deg)}
.prism-slot-mixer .prism-color-field{height:66px}
.prism-slot-footer{display:grid;grid-template-columns:minmax(78px,1fr) 26px auto;align-items:center;gap:5px}
.prism-slot-footer .prism-hex{min-height:27px;padding:3px 5px;gap:4px}
.prism-slot-footer .prism-hex small{display:none}
.prism-slot-footer .prism-sample-screen{min-height:27px;padding:3px}
.prism-slot-footer .prism-sample-screen span{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
.prism-slot-footer .prism-apply{padding:5px 7px;white-space:nowrap}
.prism-swatches .prism-swatch[aria-pressed=true]::after{filter:drop-shadow(0 0 1px white)}
@media(max-width:240px){.prism-slot-footer{grid-template-columns:minmax(0,1fr) 26px}.prism-slot-footer .prism-apply{grid-column:1/-1;justify-self:end}}
.prism-color-methods{display:flex;padding:2px;border:1px solid var(--color-border-default,GrayText);border-radius:7px}
.prism-color-methods button{flex:1;text-align:center}
.prism-color-methods [aria-pressed=true]{background:var(--color-background-primary-ghost-hover,color-mix(in srgb,currentColor 10%,transparent))}
.prism-color-field{height:120px;position:relative;overflow:hidden;border-radius:7px;touch-action:none;cursor:crosshair;background:linear-gradient(to top,#000,transparent),linear-gradient(to right,#fff,transparent),var(--prism-hue)}
.prism-color-field i{position:absolute;left:var(--prism-x);top:var(--prism-y);width:13px;height:13px;border:2px solid white;border-radius:50%;transform:translate(-50%,-50%);box-shadow:0 0 0 1px #19242699;pointer-events:none}
.prism-hue{appearance:none;display:block;width:100%;height:11px;margin:10px 0 3px;border-radius:10px;background:linear-gradient(to right,#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00);cursor:pointer}
.prism-hue::-webkit-slider-thumb{appearance:none;width:14px;height:14px;border:2px solid white;border-radius:50%;background:var(--prism-hue);box-shadow:0 0 0 1px #10151a80}
.prism-hex{display:flex;align-items:center;gap:8px;padding:5px 8px;border:1px solid var(--color-border-default,GrayText);border-radius:6px;min-height:32px}
.prism-hex i{width:17px;height:17px;flex:none;border-radius:4px}
.prism-hex input{flex:1;min-width:0;color:inherit;background:none;border:0;font:12px ui-monospace,Menlo,monospace}
.prism-hex:has([aria-invalid=true]){border-color:var(--color-text-danger,#e17064)}
.prism-sample-screen,.prism-editor-actions button{display:inline-flex;justify-content:center;align-items:center;gap:6px}
.prism-pop .prism-sample-screen{border:1px solid var(--color-border-default,GrayText)}
.prism-system-color{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none}
.prism-editor-actions{display:flex;justify-content:flex-end;padding-top:10px;margin-top:2px;border-top:1px solid var(--color-border-subtle,GrayText)}
.prism-pop .prism-apply{background:var(--color-text-primary,CanvasText);color:var(--color-surface-elevated-secondary,Canvas);padding-inline:12px}
.prism-color-editor button:disabled{opacity:.45;cursor:default}
.prism-color-status{color:var(--color-text-secondary,inherit);font-size:11px}
.prism-color-status:empty{display:none}
`;

function activate({ node, onCleanup }) {
  if (!node) throw new Error(t("Prism \u9700\u8981\u542F\u7528\u5305\u5185 Node \u540E\u7AEF\u4EE5\u8BFB\u53D6\u9879\u76EE\u5F52\u5C5E\u548C\u4FDD\u5B58\u914D\u8272"));
  const controller = new AbortController();
  const portal = document.createElement("div");
  portal.className = "prism-portal";
  const style = document.createElement("style");
  style.dataset.packpierStyle = "prism";
  style.textContent = style_default;
  document.head.append(style);
  document.body.append(portal);
  let state, confirmed, signature, sidebar, appearance, reading, again, failed = false;
  let writes = Promise.resolve(), revision = 0, timer, membership;
  let pinChange, groupTimer, hasPendingPins = false;
  const pending = /* @__PURE__ */ new Set();
  const origin = crypto.randomUUID();
  const controls = createControls({ root: portal, signal: controller.signal, getState: () => state, save });
  const groups = createGroupView(() => appearance?.refreshNow());
  function paintState(immediate = false) {
    if (!confirmed || controller.signal.aborted) return;
    if (state && state.account !== confirmed.account) {
      groups.clear();
      controls.reset();
    }
    const preferences = { ...confirmed.preferences, colors: { ...confirmed.preferences.colors }, inheritance: { ...confirmed.preferences.inheritance } };
    for (const { account, operation } of pending) {
      if (account !== confirmed.account) continue;
      if (operation.type === "mode") preferences.mode = operation.value;
      else applyColorEdit(preferences, operation);
    }
    state = { ...confirmed, preferences };
    if (setLanguage(confirmed.language)) controls.translate();
    controls.syncPalette(preferences);
    if (immediate) appearance?.refreshNow();
    else appearance?.refresh();
  }
  function save(operation) {
    const edit = { account: state.account, operation, origin };
    pending.add(edit);
    paintState(true);
    const action = writes.then(async () => {
      if (controller.signal.aborted || edit.account !== confirmed?.account) throw new Error("\u4FA7\u680F\u5DF2\u5207\u6362");
      const result = await node.invoke("update", edit);
      if (result.account === confirmed?.account) {
        revision++;
        confirmed = result;
        signature = JSON.stringify(result);
      }
    }).finally(() => {
      pending.delete(edit);
      paintState(true);
    });
    writes = action.catch(() => {
    });
    return action;
  }
  const observer = new MutationObserver(() => {
    if (!sidebar?.isConnected) connect();
  });
  function nextRead(delay = 6e4) {
    clearTimeout(timer);
    if (sidebar?.isConnected && !document.hidden) timer = setTimeout(refresh, delay);
  }
  function connect() {
    const next = document.querySelector("[data-sidebar-navigation-root]");
    if (sidebar === next && appearance) return;
    observer.disconnect();
    clearTimeout(timer);
    clearTimeout(groupTimer);
    groups.clear();
    appearance?.dispose();
    appearance = null;
    controls.reset();
    sidebar = next;
    membership = null;
    pinChange = null;
    hasPendingPins = false;
    if (!next) {
      if (!document.hidden) observer.observe(document.body, { childList: true, subtree: true });
      return;
    }
    for (let parent = next.parentElement; parent; parent = parent.parentElement) {
      observer.observe(parent, { childList: true });
    }
    mountPrismSidebar({
      mode: "all",
      palette: PALETTE,
      getClientBindings: () => state?.clientBindings,
      projectColor: (row) => state ? projectTint(row, state) : null,
      chatColor: (row) => state ? chatTint(row, state) : null,
      layoutRows(rows, section) {
        // This signature tracks the DOM. Resolving a client ID must not start a new refresh window.
        const keys = rows.map((row) => threadKey(readThread(row))).join("\n");
        if (membership !== null && keys !== membership) {
          pinChange = { at: performance.now(), reads: 0 };
          clearTimeout(groupTimer);
          nextRead(250);
        }
        membership = keys;
        if (!state) return;
        const view = makeLayout(rows, state);
        hasPendingPins = view.pending.size > 0;
        const remaining = pinChange ? pinChange.at + 400 - performance.now() : 0;
        if (pinChange && (!pinChange.reads || remaining > 0)) {
          groups.leaveNative(view.pending);
          if (pinChange.reads) {
            clearTimeout(groupTimer);
            groupTimer = setTimeout(() => appearance?.refreshNow(), remaining);
          }
        } else {
          groups.render(section, view, state);
        }
        controls.updateToolbar(section, state.preferences.mode);
        return view;
      }
    });
    appearance = window.__prismNativeSidebarV1;
    if (!document.hidden) void refresh();
  }
  async function read() {
    do {
      again = false;
      try {
        const before = revision;
        const requestedFor = pinChange;
        const current = await node.invoke("snapshot", {});
        if (controller.signal.aborted) return;
        if (revision !== before) {
          again = true;
          continue;
        }
        const pinRead = requestedFor && requestedFor === pinChange && requestedFor.reads < 2;
        if (pinRead) requestedFor.reads++;
        const encoded = JSON.stringify(current);
        if (encoded !== signature) {
          confirmed = current;
          signature = encoded;
          paintState(true);
        } else if (pinRead) appearance?.refreshNow();
        failed = false;
      } catch (error) {
        if (!controller.signal.aborted) {
          groups.clear();
          confirmed = state = null;
          signature = null;
          controls.reset();
          appearance?.refreshNow();
          if (!failed) controls.report(error.message || String(error));
          failed = true;
        }
      }
    } while (again && !controller.signal.aborted);
  }
  function refresh() {
    if (!sidebar?.isConnected || document.hidden || controller.signal.aborted) return;
    if (reading) {
      again = true;
      return reading;
    }
    clearTimeout(timer);
    reading = read().finally(() => {
      reading = null;
      if (controller.signal.aborted) return;
      if (failed) nextRead(3e3);
      else if (pinChange?.reads === 0) nextRead(Math.max(0, pinChange.at + 250 - performance.now()));
      else if (pinChange?.reads === 1 && hasPendingPins) nextRead(250);
      else nextRead();
    });
    return reading;
  }
  function resume() {
    if (document.hidden) {
      clearTimeout(timer);
      if (!sidebar?.isConnected) observer.disconnect();
    } else if (!sidebar?.isConnected) connect();
    else void refresh();
  }
  document.addEventListener("visibilitychange", resume, { signal: controller.signal });
  const unsubscribe = node.on("changed", (event) => {
    if (event?.origin !== origin) void refresh();
  });
  onCleanup(() => {
    controller.abort();
    clearTimeout(timer);
    clearTimeout(groupTimer);
    unsubscribe();
    observer.disconnect();
    groups.clear();
    appearance?.dispose();
    controls.dispose();
    style.remove();
    portal.remove();
  });
  if (!document.hidden) connect();
}
export {
  activate
};
