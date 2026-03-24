import 'package:shared_preferences/shared_preferences.dart';

/// Returns the current language key (e.g. 'English', 'Hindi') from prefs.
Future<String> currentLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('mizhi_language') ?? 'English';
}

/// Welcome messages per language
const Map<String, String> welcomeMessages = {
  'English': 'Welcome to Mizhi. Tap Street Smart or Money Sense to begin.',
  'Hindi': 'मिज़ी में आपका स्वागत है। शुरू करने के लिए स्ट्रीट स्मार्ट या मनी सेंस दबाएँ।',
  'Tamil': 'மிழிக்கு வரவேற்கிறோம். தொடங்க �ட்ரீட் ஸ்மார்ட் அல்லது மணி சென்ஸ் தட்டவும்.',
  'Malayalam': 'മിഴിയിലേക്ക് സ്വാഗതം. ആരംഭിക്കാൻ സ്ട്രീറ്റ് സ്മാർട്ട് അല്ലെങ്കിൽ മണി സെൻസ് ടാപ്പ് ചെയ്യൂ.',
  'Telugu': 'మిజీకి స్వాగతం. ప్రారంభించడానికి స్ట్రీట్ స్మార్ట్ లేదా మనీ సెన్స్ నొక్కండి.',
};

/// Localized alert messages — keys match the English label from the COCO model.
/// Each sub-map provides the spoken text in that language.
const Map<String, Map<String, String>> localizedAlerts = {
  'Hindi': {
    'person': 'सामने व्यक्ति है',
    'car': 'कार आपके रास्ते पर',
    'truck': 'भारी वाहन आगे है। रुकें',
    'bus': 'बस आ रही है',
    'motorcycle': 'पास में मोटरसाइकिल। सावधान',
    'bicycle': 'पास में साइकिल',
    'train': 'पास में ट्रेन। सावधान',
    'traffic light': 'ट्रैफिक सिग्नल आगे',
    'stop sign': 'स्टॉप साइन आगे',
    'dog': 'पास में कुत्ता',
    'cat': 'पास में बिल्ली',
    'chair': 'रास्ते में कुर्सी',
    'fire hydrant': 'रास्ते में फायर हाइड्रेंट',
    'cow': 'सड़क पर गाय। रुकें',
    'horse': 'सड़क पर घोड़ा। रुकें',
    'elephant': 'हाथी आगे। रुकें',
    'knife': 'पास में चाकू। सावधान',
    'scissors': 'तेज़ वस्तु पास में। सावधान',
    'potted plant': 'रास्ते में पौधा',
    'bench': 'रास्ते में बेंच',
    'dining table': 'रास्ते में मेज़',
    'bottle': 'रास्ते में बोतल',
    'suitcase': 'रास्ते पर सामान',
    'backpack': 'बैग मिला',
    'cell phone': 'फ़ोन मिला',
    'tv': 'आगे टीवी',
    'laptop': 'सतह पर लैपटॉप',
    'refrigerator': 'आगे फ्रिज',
    'sink': 'आगे सिंक',
    'bed': 'आगे बिस्तर',
    'toilet': 'आगे शौचालय',
    'couch': 'रास्ता रोक रहा सोफा',
  },
  'Tamil': {
    'person': 'முன்னால் நபர்',
    'car': 'உங்கள் பாதையில் கார்',
    'truck': 'பெரிய வாகனம் முன்னால். நிறுத்துங்கள்',
    'bus': 'பேருந்து வருகிறது',
    'motorcycle': 'அருகில் மோட்டார்சைக்கிள். கவனம்',
    'bicycle': 'அருகில் மிதிவண்டி',
    'train': 'அருகில் ரயில். கவனம்',
    'traffic light': 'முன்னால் போக்குவரத்து சிக்னல்',
    'stop sign': 'முன்னால் நிறுத்த அடையாளம்',
    'dog': 'அருகில் நாய்',
    'cat': 'அருகில் பூனை',
    'chair': 'பாதையில் நாற்காலி',
    'cow': 'சாலையில் மாடு. நிறுத்துங்கள்',
    'knife': 'அருகில் கத்தி. கவனம்',
    'bottle': 'பாதையில் பாட்டில்',
    'suitcase': 'பாதையில் பொருட்கள்',
  },
  'Malayalam': {
    'person': 'മുന്നിൽ ആൾ ഉണ്ട്',
    'car': 'നിങ്ങളുടെ വഴിയിൽ കാർ',
    'truck': 'മുന്നിൽ വലിയ വാഹനം. നിർത്തൂ',
    'bus': 'ബസ് വരുന്നു',
    'motorcycle': 'അടുത്ത് മോട്ടോർസൈക്കിൾ. ശ്രദ്ധിക്കൂ',
    'bicycle': 'അടുത്ത് സൈക്കിൾ',
    'train': 'അടുത്ത് ട്രെയിൻ. ശ്രദ്ധിക്കൂ',
    'traffic light': 'മുന്നിൽ ട്രാഫിക് സിഗ്നൽ',
    'stop sign': 'മുന്നിൽ സ്റ്റോപ്പ് സൈൻ',
    'dog': 'അടുത്ത് നായ',
    'cat': 'അടുത്ത് പൂച്ച',
    'chair': 'വഴിയിൽ കസേര',
    'cow': 'റോഡിൽ പശു. നിർത്തൂ',
    'knife': 'അടുത്ത് കത്തി. ശ്രദ്ധിക്കൂ',
    'bottle': 'വഴിയിൽ കുപ്പി',
    'suitcase': 'വഴിയിൽ ലഗേജ്',
  },
  'Telugu': {
    'person': 'ముందు వ్యక్తి ఉన్నారు',
    'car': 'మీ దారిలో కారు',
    'truck': 'ముందు భారీ వాహనం. ఆపండి',
    'bus': 'బస్ వస్తోంది',
    'motorcycle': 'దగ్గరలో మోటార్ సైకిల్. జాగ్రత్త',
    'bicycle': 'దగ్గరలో సైకిల్',
    'train': 'దగ్గరలో రైలు. జాగ్రత్త',
    'traffic light': 'ముందు ట్రాఫిక్ సిగ్నల్',
    'stop sign': 'ముందు స్టాప్ సైన్',
    'dog': 'దగ్గరలో కుక్క',
    'cat': 'దగ్గరలో పిల్లి',
    'chair': 'దారిలో కుర్చీ',
    'cow': 'రోడ్డుపై ఆవు. ఆపండి',
    'knife': 'దగ్గరలో కత్తి. జాగ్రత్త',
    'bottle': 'దారిలో బాటిల్',
    'suitcase': 'దారిలో లగేజీ',
  },
};

/// Get the localized alert message for a detection label.
/// Falls back to the English [alertMessages] map.
String getLocalizedAlert(String label, String language) {
  if (language != 'English') {
    final langMap = localizedAlerts[language];
    if (langMap != null) {
      final msg = langMap[label] ?? langMap[label.toLowerCase()];
      if (msg != null) return msg;
    }
  }
  // Empty means caller should use default English fallback
  return '';
}

/// Currency announcement templates per language.
/// Use {d} as placeholder for denomination.
const Map<String, String> currencyTemplates = {
  'English': 'This is a {d} rupee note',
  'Hindi': 'ये {d} रुपये का नोट है',
  'Tamil': 'இது {d} ரூபாய் நோட்டு',
  'Malayalam': 'ഇത് {d} രൂപ നോട്ടാണ്',
  'Telugu': 'ఇది {d} రూపాయల నోటు',
};

/// Build a currency announcement in the given language.
String currencyAnnouncement(String denomination, String language) {
  final tpl = currencyTemplates[language] ?? currencyTemplates['English']!;
  return tpl.replaceAll('{d}', denomination);
}
