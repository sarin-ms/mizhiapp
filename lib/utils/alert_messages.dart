const Map<String, String> alertMessages = {
  // People
  'person': 'Person ahead',

  // Vehicles — high priority
  'car': 'Car on your path',
  'truck': 'Heavy vehicle ahead. Stop',
  'bus': 'Bus approaching',
  'motorcycle': 'Motorcycle nearby. Be careful',
  'bicycle': 'Cyclist nearby',
  'boat': 'Boat nearby',
  'airplane': 'Airplane overhead',
  'train': 'Train nearby. Be careful',

  // Road objects
  'traffic light': 'Traffic signal ahead',
  'stop sign': 'Stop sign ahead',
  'parking meter': 'Parking meter nearby',
  'fire hydrant': 'Fire hydrant on path',

  // Animals
  'cat': 'Cat nearby',
  'dog': 'Dog nearby',
  'horse': 'Horse on road. Stop',
  'sheep': 'Animal on road',
  'cow': 'Cow on road. Stop',
  'elephant': 'Elephant ahead. Stop',
  'bear': 'Bear nearby. Stop',
  'zebra': 'Animal on road',
  'giraffe': 'Animal ahead',
  'bird': 'Bird nearby',

  // Furniture / indoor obstacles
  'chair': 'Chair on your path',
  'couch': 'Couch blocking path',
  'bed': 'Bed ahead',
  'dining table': 'Table on your path',
  'toilet': 'Toilet ahead',
  'bench': 'Bench on your path',

  // Electronics
  'tv': 'Television ahead',
  'laptop': 'Laptop on surface',
  'mouse': 'Mouse on surface',
  'remote': 'Remote nearby',
  'keyboard': 'Keyboard nearby',
  'cell phone': 'Phone detected',
  'microwave': 'Microwave ahead',
  'oven': 'Oven ahead',
  'toaster': 'Toaster nearby',
  'refrigerator': 'Refrigerator ahead',

  // Kitchen
  'bottle': 'Bottle on path',
  'wine glass': 'Glass nearby',
  'cup': 'Cup nearby',
  'fork': 'Fork nearby',
  'knife': 'Knife nearby. Be careful',
  'spoon': 'Spoon nearby',
  'bowl': 'Bowl on surface',
  'banana': 'Food item nearby',
  'apple': 'Food item nearby',
  'sandwich': 'Food item nearby',
  'orange': 'Food item nearby',
  'pizza': 'Food item nearby',
  'cake': 'Food item nearby',

  // Bags / carried items
  'backpack': 'Backpack detected',
  'umbrella': 'Umbrella nearby',
  'handbag': 'Bag on path',
  'tie': 'Person nearby',
  'suitcase': 'Luggage on path',

  // Sports
  'frisbee': 'Object in air',
  'skis': 'Sports equipment nearby',
  'snowboard': 'Sports equipment nearby',
  'sports ball': 'Ball on path',
  'kite': 'Object in air',
  'baseball bat': 'Object nearby',
  'baseball glove': 'Object nearby',
  'skateboard': 'Skateboard on path',
  'surfboard': 'Board on path',
  'tennis racket': 'Racket nearby',

  // Outdoor
  'potted plant': 'Plant on path',
  'vase': 'Fragile object nearby',
  'clock': 'Clock on wall',
  'scissors': 'Sharp object nearby. Be careful',
  'teddy bear': 'Object on floor',
  'hair drier': 'Object nearby',
  'toothbrush': 'Object nearby',
  'book': 'Book on surface',
  'sink': 'Sink ahead',
};

// Priority levels — higher number = announce first
const Map<String, int> alertPriority = {
  // Highest — immediate danger
  'person': 5,
  'car': 5,
  'truck': 5,
  'bus': 5,
  'motorcycle': 5,
  'train': 5,
  'horse': 5,
  'cow': 5,
  'elephant': 5,
  'bear': 5,

  // High — path obstacles
  'bicycle': 4,
  'dog': 4,
  'chair': 4,
  'couch': 4,
  'dining table': 4,
  'bench': 4,
  'suitcase': 4,
  'skateboard': 4,

  // Medium — road signs
  'traffic light': 3,
  'stop sign': 3,
  'fire hydrant': 3,
  'potted plant': 3,
  'backpack': 3,

  // Low — informational
  'bottle': 2,
  'cup': 2,
  'laptop': 2,
  'cell phone': 2,
  'tv': 2,
  'refrigerator': 2,
  'bed': 2,
  'toilet': 2,
  'sink': 2,
  'knife': 2,
  'scissors': 2,
};

// Minimum confidence to trigger alert
const double kMinConfidence = 0.45;

// Minimum seconds between same alert repeating (mutable — updated from Settings)
int kAlertCooldownSeconds = 3;
