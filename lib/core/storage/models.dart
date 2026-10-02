enum CollectibleType { coin, banknote }

enum RarityLevel {
  /// No rarity data source exists for this coin; never inferred from metal or age.
  notAssessed,
  common,
  uncommon,
  rare,
  veryRare,
  extremelyRare,
  museumGrade;

  String get displayName {
    switch (this) {
      case RarityLevel.notAssessed:
        return 'Not assessed';
      case RarityLevel.common:
        return 'Common';
      case RarityLevel.uncommon:
        return 'Uncommon';
      case RarityLevel.rare:
        return 'Rare';
      case RarityLevel.veryRare:
        return 'Very Rare';
      case RarityLevel.extremelyRare:
        return 'Extremely Rare';
      case RarityLevel.museumGrade:
        return 'Museum Grade';
    }
  }
}

class CollectibleModel {
  final String id;
  final CollectibleType type;
  final String name;
  final String country;
  final int year;
  final String denomination;
  final String mintMark;
  final String composition;
  final double weightG;
  final double diameterMm;
  final double thicknessMm;
  final String shape;
  final String edgeType;
  final String mint;
  final String designer;
  final String historicalPeriod;
  final RarityLevel rarity;
  /// Identification confidence (0..1) recorded at scan time, or null when none
  /// was recorded. This is NOT an authenticity score: photo recognition cannot
  /// authenticate a coin.
  final double? identificationConfidence;

  /// Evidence recorded for the identification (empty when none was saved).
  final List<String> evidenceSummary;
  final String estimatedGrade;
  final String gradeExplanation;
  final String frontImageUrl;
  final String backImageUrl;
  final String historicalInfo;
  final String category;

  // Market valuation
  final double retailPrice;
  final double auctionPrice;
  final double dealerPrice;
  final double collectorPrice;
  final double minPrice;
  final double maxPrice;
  final double priceTrendPercentage; // 12.5 means +12.5%
  final String investmentRating; // e.g. "A+", "B"

  // Error coin details (optional)
  final String? errorType;
  final String? errorDescription;

  // Banknote security details (optional)
  final String? governorSignature;
  final String? serialNumber;
  final String? watermarkDescription;
  final String? securityThreadDescription;

  CollectibleModel({
    required this.id,
    required this.type,
    required this.name,
    required this.country,
    required this.year,
    required this.denomination,
    required this.mintMark,
    required this.composition,
    required this.weightG,
    required this.diameterMm,
    required this.thicknessMm,
    required this.shape,
    required this.edgeType,
    required this.mint,
    required this.designer,
    required this.historicalPeriod,
    required this.rarity,
    required this.identificationConfidence,
    required this.evidenceSummary,
    required this.estimatedGrade,
    required this.gradeExplanation,
    required this.frontImageUrl,
    required this.backImageUrl,
    required this.historicalInfo,
    required this.category,
    required this.retailPrice,
    required this.auctionPrice,
    required this.dealerPrice,
    required this.collectorPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.priceTrendPercentage,
    required this.investmentRating,
    this.errorType,
    this.errorDescription,
    this.governorSignature,
    this.serialNumber,
    this.watermarkDescription,
    this.securityThreadDescription,
  });
}

class PortfolioItemModel {
  final String id;
  final CollectibleModel collectible;
  final double purchasePrice;
  final DateTime purchaseDate;
  final String purchaseLocation;
  final String seller;
  final String storageLocation;
  final String notes;
  final bool isFavorite;

  PortfolioItemModel({
    required this.id,
    required this.collectible,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.purchaseLocation,
    required this.seller,
    required this.storageLocation,
    required this.notes,
    required this.isFavorite,
  });

  PortfolioItemModel copyWith({
    double? purchasePrice,
    DateTime? purchaseDate,
    String? purchaseLocation,
    String? seller,
    String? storageLocation,
    String? notes,
    bool? isFavorite,
  }) {
    return PortfolioItemModel(
      id: id,
      collectible: collectible,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseLocation: purchaseLocation ?? this.purchaseLocation,
      seller: seller ?? this.seller,
      storageLocation: storageLocation ?? this.storageLocation,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class MarketplaceListingModel {
  final String id;
  final CollectibleModel collectible;
  final String sellerName;
  final String sellerAvatar;
  final bool isSellerVerified;
  final double price;
  final String status; // active, pending, sold
  final bool escrowReady;
  final int views;
  final int offersCount;

  MarketplaceListingModel({
    required this.id,
    required this.collectible,
    required this.sellerName,
    required this.sellerAvatar,
    required this.isSellerVerified,
    required this.price,
    required this.status,
    required this.escrowReady,
    required this.views,
    required this.offersCount,
  });
}

class AchievementModel {
  final String id;
  final String title;
  final String description;
  final String badgeIcon; // e.g. "gold_cup", "globe"
  final DateTime? unlockedAt;
  final int xpAwarded;

  AchievementModel({
    required this.id,
    required this.title,
    required this.description,
    required this.badgeIcon,
    this.unlockedAt,
    required this.xpAwarded,
  });

  bool get isUnlocked => unlockedAt != null;
}

class LessonModel {
  final String id;
  final String title;
  final String category; // Basics, Errors, Storage, Counterfeits
  final String body;
  final String author;
  final String readTime;
  final String imageUrl;
  final bool isBookmarked;

  LessonModel({
    required this.id,
    required this.title,
    required this.category,
    required this.body,
    required this.author,
    required this.readTime,
    required this.imageUrl,
    required this.isBookmarked,
  });

  LessonModel copyWith({bool? isBookmarked}) {
    return LessonModel(
      id: id,
      title: title,
      category: category,
      body: body,
      author: author,
      readTime: readTime,
      imageUrl: imageUrl,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}

class CollectorProfileModel {
  final String username;
  final String bio;
  final String rankName;
  final int level;
  final int globalRanking;
  final int reputationRating; // out of 100
  final int totalScans;
  final bool isVerifiedCollector;
  final List<String> badgeIds;
  final int followersCount;
  final int followingCount;

  CollectorProfileModel({
    required this.username,
    required this.bio,
    required this.rankName,
    required this.level,
    required this.globalRanking,
    required this.reputationRating,
    required this.totalScans,
    required this.isVerifiedCollector,
    required this.badgeIds,
    required this.followersCount,
    required this.followingCount,
  });
}

class SeriesCompletionModel {
  final String id;
  final String title;
  final String country;
  final int totalCount;
  final int ownedCount;
  final String description;
  final List<String> targetYears;

  SeriesCompletionModel({
    required this.id,
    required this.title,
    required this.country,
    required this.totalCount,
    required this.ownedCount,
    required this.description,
    required this.targetYears,
  });

  double get progressPercentage =>
      totalCount == 0 ? 0.0 : ownedCount / totalCount;
}
