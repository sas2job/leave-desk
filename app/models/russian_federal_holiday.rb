class RussianFederalHoliday
  FIXED_DATES = [
    [ 1, 1 ], [ 1, 2 ], [ 1, 3 ], [ 1, 4 ], [ 1, 5 ], [ 1, 6 ], [ 1, 7 ], [ 1, 8 ],
    [ 2, 23 ], [ 3, 8 ], [ 5, 1 ], [ 5, 9 ], [ 6, 12 ], [ 11, 4 ]
  ].freeze

  def self.on?(date)
    FIXED_DATES.include?([ date.month, date.day ])
  end
end
