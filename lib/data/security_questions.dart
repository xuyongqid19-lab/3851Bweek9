const securityQuestionPresets = <String>[
  'What is the name of your first school?',
  'What is your favourite food?',
  'What city were you born in?',
  'What is your childhood nickname?',
  'What was the name of your first pet?',
];

const customSecurityQuestion = 'Custom Security Question';

String normalizeSecurityQuestion(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
