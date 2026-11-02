enum VoiceAction {
  street,
  money,
  settings,
  emergencyContact,
  home,
  back,
  help,
  emergencyCall,
  flashOn,
  flashOff,
  vibrationOn,
  vibrationOff,
  voiceOn,
  voiceOff,
  volumeUp,
  volumeDown,
  volume,
  language,
  speed,
  cooldown,
}

class VoiceCommand {
  final VoiceAction action;
  final String? value;
  final int? number;
  const VoiceCommand(this.action, {this.value, this.number});
}

String normalizeCommand(String text) {
  var result = text.toLowerCase().replaceAll(RegExp(r'[.,!?;:।…]'), ' ').trim();
  for (final prefix in [
    'please ',
    'can you ',
    'could you ',
    'mizhi ',
    'कृपया ',
    'தயவுசெய்து ',
    'ദയവായി ',
    'దయచేసి ',
  ]) {
    if (result.startsWith(prefix)) result = result.substring(prefix.length);
  }
  for (final digits in [
    '०१२३४५६७८९',
    '௦௧௨௩௪௫௬௭௮௯',
    '൦൧൨൩൪൫൬൭൮൯',
    '౦౧౨౩౪౫౬౭౮౯',
  ]) {
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(digits[i], '$i');
    }
  }
  return result.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _phrases = <VoiceAction, List<String>>{
  VoiceAction.street: [
    'open street smart',
    'open street smart mode',
    'street smart',
    'street smart mode',
    'open street',
    'switch to street smart',
    'start object detection',
    'open object detection',
    'स्ट्रीट स्मार्ट खोलो',
    'स्ट्रीट स्मार्ट खोलें',
    'वस्तु पहचान खोलो',
    'ஸ்ட்ரீட் ஸ்மார்ட் திற',
    'ஸ்ட்ரீட் ஸ்மார்ட் திறக்கவும்',
    'பொருள் கண்டறிதல் திற',
    'സ്ട്രീറ്റ് സ്മാർട്ട് തുറക്കുക',
    'സ്ട്രീറ്റ് സ്മാർട്ട് തുറക്കൂ',
    'വസ്തു തിരിച്ചറിയൽ തുറക്കുക',
    'స్ట్రీట్ స్మార్ట్ తెరువు',
    'స్ట్రీట్ స్మార్ట్ తెరవండి',
    'వస్తువుల గుర్తింపు తెరువు',
  ],
  VoiceAction.money: [
    'open money sense',
    'open money cents',
    'open money sense mode',
    'money sense',
    'money cents',
    'money sense mode',
    'open money',
    'money mode',
    'switch to money sense',
    'open currency mode',
    'start currency detection',
    'मनी सेंस खोलो',
    'मनी सेंस खोलें',
    'नोट पहचान खोलो',
    'மணி சென்ஸ் திற',
    'மணி சென்ஸ் திறக்கவும்',
    'பண அறிதல் திற',
    'മണി സെൻസ് തുറക്കുക',
    'മണി സെൻസ് തുറക്കൂ',
    'പണം തിരിച്ചറിയൽ തുറക്കുക',
    'మనీ సెన్స్ తెరువు',
    'మనీ సెన్స్ తెరవండి',
    'నోట్ల గుర్తింపు తెరువు',
  ],
  VoiceAction.settings: [
    'open settings',
    'settings',
    'settings menu',
    'change settings',
    'go to settings',
    'सेटिंग्स खोलो',
    'सेटिंग्स खोलें',
    'அமைப்புகள் திற',
    'அமைப்புகள் திறக்கவும்',
    'ക്രമീകരണങ്ങൾ തുറക്കുക',
    'ക്രമീകരണങ്ങൾ തുറക്കൂ',
    'సెట్టింగులు తెరువు',
    'సెట్టింగులు తెరవండి',
  ],
  VoiceAction.emergencyContact: [
    'open emergency contact',
    'open emergency contacts',
    'emergency contact',
    'आपातकालीन संपर्क खोलो',
    'அவசர தொடர்பு திற',
    'അടിയന്തര സമ്പർക്കം തുറക്കുക',
    'అత్యవసర సంప్రదింపు తెరువు',
  ],
  VoiceAction.home: [
    'go home',
    'open home',
    'home screen',
    'go to home',
    'होम खोलो',
    'होम पर जाओ',
    'முகப்பு திற',
    'முகப்புக்கு செல்',
    'പ്രധാന പേജിലേക്ക് പോകുക',
    'ഹോം തുറക്കുക',
    'హోమ్ తెరువు',
    'హోమ్‌కు వెళ్ళు',
  ],
  VoiceAction.back: [
    'go back',
    'back',
    'move back',
    'previous screen',
    'stop checking',
    'वापस जाओ',
    'वापस जाएँ',
    'पीछे जाओ',
    'பின்செல்',
    'பின்னால் செல்',
    'பின்செல்லவும்',
    'തിരികെ പോകുക',
    'തിരികെ പോകൂ',
    'പുറകിലേക്ക് പോകുക',
    'వెనక్కి వెళ్ళు',
    'వెనక్కి వెళ్ళండి',
  ],
  VoiceAction.help: [
    'help',
    'help me',
    'voice command help',
    'मदद',
    'सहायता',
    'உதவி',
    'குரல் கட்டளை உதவி',
    'സഹായം',
    'ശബ്ദ നിർദ്ദേശ സഹായം',
    'సహాయం',
    'వాయిస్ ఆదేశాల సహాయం',
  ],
  VoiceAction.emergencyCall: [
    'help me call',
    'call emergency contact',
    'मदद के लिए कॉल करो',
    'आपातकालीन संपर्क को कॉल करो',
    'உதவிக்கு அழை',
    'அவசர தொடர்பை அழை',
    'സഹായത്തിന് വിളിക്കൂ',
    'അടിയന്തര സമ്പർക്കത്തെ വിളിക്കുക',
    'సహాయం కోసం కాల్ చేయి',
    'అత్యవసర సంప్రదింపుకు కాల్ చేయి',
  ],
  VoiceAction.flashOn: [
    'flash on',
    'flashlight on',
    'turn on flashlight',
    'turn flash on',
    'फ़्लैश चालू करो',
    'फ़्लैशलाइट चालू करो',
    'விளக்கு இயக்கு',
    'விளக்கை இயக்கு',
    'ഫ്ലാഷ് ഓൺ',
    'ഫ്ലാഷ് ഓൺ ചെയ്യുക',
    'ఫ్లాష్ ఆన్',
    'ఫ్లాష్ ఆన్ చేయి',
  ],
  VoiceAction.flashOff: [
    'flash off',
    'flashlight off',
    'turn off flashlight',
    'turn flash off',
    'फ़्लैश बंद करो',
    'फ़्लैशलाइट बंद करो',
    'விளக்கு நிறுத்து',
    'விளக்கை நிறுத்து',
    'ഫ്ലാഷ് ഓഫ്',
    'ഫ്ലാഷ് ഓഫ് ചെയ്യുക',
    'ఫ్లాష్ ఆఫ్',
    'ఫ్లాష్ ఆఫ్ చేయి',
  ],
  VoiceAction.vibrationOn: [
    'vibration on',
    'enable vibration',
    'turn on vibration',
    'कंपन चालू करो',
    'அதிர்வு இயக்கு',
    'വൈബ്രേഷൻ ഓൺ',
    'వైబ్రేషన్ ఆన్ చేయి',
  ],
  VoiceAction.vibrationOff: [
    'vibration off',
    'disable vibration',
    'turn off vibration',
    'कंपन बंद करो',
    'அதிர்வு நிறுத்து',
    'വൈബ്രേഷൻ ഓഫ്',
    'వైబ్రేషన్ ఆఫ్ చేయి',
  ],
  VoiceAction.voiceOn: [
    'voice on',
    'unmute voice',
    'enable voice feedback',
    'आवाज़ चालू करो',
    'குரல் இயக்கு',
    'ശബ്ദ അറിയിപ്പ് ഓൺ',
    'వాయిస్ ఆన్ చేయి',
  ],
  VoiceAction.voiceOff: [
    'voice off',
    'mute voice',
    'disable voice feedback',
    'आवाज़ बंद करो',
    'குரல் நிறுத்து',
    'ശബ്ദ അറിയിപ്പ് ഓഫ്',
    'వాయిస్ ఆఫ్ చేయి',
  ],
  VoiceAction.volumeUp: [
    'volume up',
    'increase volume',
    'turn volume up',
    'आवाज़ बढ़ाओ',
    'आवाज़ बढ़ाएँ',
    'குரல் அளவை அதிகரி',
    'ശബ്ദം കൂട്ടുക',
    'శబ్దం పెంచు',
  ],
  VoiceAction.volumeDown: [
    'volume down',
    'decrease volume',
    'turn volume down',
    'आवाज़ कम करो',
    'குரல் அளவை குறை',
    'ശബ്ദം കുറയ്ക്കുക',
    'శబ్దం తగ్గించు',
  ],
};

const _speedPhrases = {
  'Slow': [
    'slow speed',
    'speak slowly',
    'speak slower',
    'set speed to slow',
    'धीरे बोलो',
    'धीरे बोलें',
    'மெதுவாக பேசு',
    'പതുക്കെ സംസാരിക്കുക',
    'నెమ్మదిగా మాట్లాడు',
  ],
  'Normal': [
    'normal speed',
    'set speed to normal',
    'सामान्य गति',
    'இயல்பான வேகம்',
    'സാധാരണ വേഗം',
    'సాధారణ వేగం',
  ],
  'Fast': [
    'fast speed',
    'speak faster',
    'set speed to fast',
    'तेज़ बोलो',
    'வேகமாக பேசு',
    'വേഗത്തിൽ സംസാരിക്കുക',
    'వేగంగా మాట్లాడు',
  ],
};
const _languageAliases = {
  'English': [
    'english',
    'अंग्रेज़ी',
    'अंग्रेजी',
    'ஆங்கிலம்',
    'ஆங்கிலத்திற்கு',
    'ഇംഗ്ലീഷ്',
    'ഇംഗ്ലീഷിലേക്ക്',
    'ఇంగ్లీష్',
    'ఇంగ్లీషుకు',
  ],
  'Hindi': [
    'hindi',
    'हिंदी',
    'हिन्दी',
    'இந்தி',
    'இந்திக்கு',
    'ഹിന്ദി',
    'ഹിന്ദിയിലേക്ക്',
    'హిందీ',
    'హిందీకి',
  ],
  'Tamil': [
    'tamil',
    'तमिल',
    'தமிழ்',
    'தமிழுக்கு',
    'തമിഴ്',
    'തമിഴിലേക്ക്',
    'తమిళం',
    'తమిళానికి',
  ],
  'Malayalam': [
    'malayalam',
    'मलयालम',
    'மலையாளம்',
    'மலையாளத்திற்கு',
    'മലയാളം',
    'മലയാളത്തിലേക്ക്',
    'మలయాళం',
    'మలయాళానికి',
  ],
  'Telugu': [
    'telugu',
    'तेलुगु',
    'తెలుగు',
    'తెలుగుకు',
    'தெலுங்கு',
    'தெலுங்கிற்கு',
    'തെലുങ്ക്',
    'തെലുങ്കിലേക്ക്',
  ],
};

VoiceCommand? parseVoiceCommand(String input) {
  final text = normalizeCommand(input);
  for (final entry in _phrases.entries) {
    if (entry.value.any((phrase) => normalizeCommand(phrase) == text)) {
      return VoiceCommand(entry.key);
    }
  }
  for (final entry in _speedPhrases.entries) {
    if (entry.value.any((phrase) => normalizeCommand(phrase) == text)) {
      return VoiceCommand(VoiceAction.speed, value: entry.key);
    }
  }
  for (final pattern in [
    r'^(?:change|set|switch) (?:app )?language to (.+)$',
    r'^भाषा (.+?)(?: में)? (?:करें|करो|बदलें|बदलो)$',
    r'^மொழியை (.+?) (?:மாற்று|மாற்றவும்)$',
    r'^ഭാഷ (.+?) (?:മാറ്റുക|മാറ്റൂ)$',
    r'^భాష (.+?) (?:మార్చు|మార్చండి)$',
    r'^(?:language|भाषा|மொழி|ഭാഷ|భాష) (.+)$',
  ]) {
    final name = RegExp(pattern).firstMatch(text)?.group(1);
    if (name == null) continue;
    for (final entry in _languageAliases.entries) {
      if (entry.value.contains(name)) {
        return VoiceCommand(VoiceAction.language, value: entry.key);
      }
    }
  }
  for (final pattern in [
    r'^(?:set |change )?volume(?: to)? (\d{1,3})(?: percent)?$',
    r'^आवाज़(?: का स्तर)? (\d{1,3})(?: प्रतिशत)?(?: करो| करें)?$',
    r'^குரல் அளவு (\d{1,3})(?: சதவீதம்)?$',
    r'^ശബ്ദം (\d{1,3})(?: ശതമാനം)?$',
    r'^వాయిస్ శబ్దం (\d{1,3})(?: శాతం)?$',
  ]) {
    final match = RegExp(pattern).firstMatch(text);
    if (match != null) {
      final amount = int.parse(match.group(1)!);
      return amount <= 100
          ? VoiceCommand(VoiceAction.volume, number: amount)
          : null;
    }
  }
  final cooldown = RegExp(
    r'^set (?:alert )?cooldown(?: to)? (\d{1,2})(?: seconds)?$',
  ).firstMatch(text);
  if (cooldown != null) {
    final amount = int.parse(cooldown.group(1)!);
    if (amount >= 1 && amount <= 10) {
      return VoiceCommand(VoiceAction.cooldown, number: amount);
    }
  }
  return null;
}
