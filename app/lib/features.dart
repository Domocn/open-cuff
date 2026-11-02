/// Every optional feature, each with its own switch in More > Features. All start off.
class Feature {
  final String key, title, subtitle, group;
  const Feature(this.key, this.title, this.subtitle, this.group);
}

const featureGroups = ['Medicines and doctor', 'Calm', 'Readings', 'House'];

const features = <Feature>[
  Feature('meds', 'Medications', 'Log doses and see your blood pressure at each dose', 'Medicines and doctor'),
  Feature('homecheck', 'NHS home check', 'Two readings, morning and evening, for 7 days. Gives the average your GP wants', 'Medicines and doctor'),
  Feature('trends', 'Trend alerts', 'Tells you about real changes over days, not one-off readings', 'Medicines and doctor'),
  Feature('goals', 'Limits and alerts', 'Your own top, bottom and pulse limits, with a calm notification', 'Medicines and doctor'),
  Feature('effects', 'Side-effect taps', 'Headache, racing heart, poor appetite, bad sleep, on edge', 'Medicines and doctor'),
  Feature('tags', 'Coffee, nicotine and exercise tags', 'Marks readings taken soon after', 'Medicines and doctor'),
  Feature('clinic', 'Clinic readings', 'Type in the GP\'s reading and compare it with home', 'Medicines and doctor'),
  Feature('calm', 'Calm mode', 'Home shows a colour and a few words. Tap to see the numbers', 'Calm'),
  Feature('streaks', 'Gentle streaks', '"5 mornings this week". Missing a day never resets anything', 'Calm'),
  Feature('reminders', 'Reading reminders', 'A quiet nudge morning and evening', 'Calm'),
  Feature('weekly', 'Sunday summary', 'Average, trend and anything worth telling your doctor', 'Calm'),
  Feature('widget', 'Home screen widget', 'Latest reading on your home screen', 'Calm'),
  Feature('guided', 'Guided reading', 'Steps and a 5-minute resting timer before you start', 'Readings'),
  Feature('quality', 'Quality check', 'Flags readings taken too close together or right after coffee or exercise', 'Readings'),
  Feature('context', 'Context from your watch', 'Last night\'s sleep and resting heart rate next to each reading', 'Readings'),
  Feature('people', 'More than one person', 'Show whose readings are on screen, with a name each', 'House'),
];
