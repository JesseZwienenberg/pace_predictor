class Activity < ApplicationRecord
    has_many :splits, dependent: :destroy
    has_many :best_efforts, dependent: :destroy

    def pace_per_km
        return 0 if distance.zero?
        (duration / 60.0) / (distance / 1000.0)
    end

    def distance_km
        distance / 1000.0
    end
end
