import '../storage/models.dart';

class MockApi {
  // Pre-configured highly detailed coins & banknotes
  static final List<CollectibleModel> collectibles = [
    CollectibleModel(
      id: 'coin_saint_gaudens',
      type: CollectibleType.coin,
      name: '1907 Saint-Gaudens Double Eagle (Ultra High Relief, Flat Rim)',
      country: 'United States',
      year: 1907,
      denomination: '\$20',
      mintMark: 'None (Philadelphia)',
      composition: '90% Gold, 10% Copper',
      weightG: 33.436,
      diameterMm: 34.0,
      thicknessMm: 2.5,
      shape: 'Round',
      edgeType: 'Lettered (* E * PLURIBUS * UNUM * * * * * * * * *)',
      mint: 'Philadelphia Mint',
      designer: 'Augustus Saint-Gaudens',
      historicalPeriod: 'Early 20th Century (1907-1933)',
      rarity: RarityLevel.museumGrade,
      authenticityConfidence: 0.99,
      authenticityReasons: [
        'Edge lettering displays correct spacing and font style matching Philadelphia dies.',
        'High relief detail sharp and consistent with master hub strikes.',
        'Surface finish exhibits correct satin texture from original minting processes.',
        'Gold content verified at approximately 90.0% through acoustic density modeling.',
      ],
      estimatedGrade: 'MS67',
      gradeExplanation:
          'Exceptional strike with nearly pristine golden-orange luster. Minor bag marks on obverse field, but overall design is incredibly sharp and fully struck. Luster remains deeply reflective.',
      frontImageUrl: 'saint_gaudens_front',
      backImageUrl: 'saint_gaudens_back',
      historicalInfo:
          'Commissioned by President Theodore Roosevelt in his effort to beautify American coinage, this Ultra High Relief version represents the pinnacle of American numismatic art. Only about 20 specimens of this relief style are known to exist, making it one of the absolute crown jewels of coin collecting.',
      category: 'Gold Coins',
      retailPrice: 2850000,
      auctionPrice: 3100000,
      dealerPrice: 2500000,
      collectorPrice: 2900000,
      minPrice: 2400000,
      maxPrice: 3200000,
      priceTrendPercentage: 18.4,
      investmentRating: 'AAA+',
    ),
    CollectibleModel(
      id: 'coin_athenian_owl',
      type: CollectibleType.coin,
      name: 'Silver Athenian Tetradrachm (Attica, Owl)',
      country: 'Ancient Greece (Athens)',
      year: -440, // 440 BC
      denomination: 'Tetradrachm',
      mintMark: 'Athens (Alpha Theta Epsilon)',
      composition: '98% Silver (Nearly Pure)',
      weightG: 17.20,
      diameterMm: 24.0,
      thicknessMm: 4.5,
      shape: 'Irregular (Hand-struck)',
      edgeType: 'Plain / Chiseled',
      mint: 'Athens Treasury Mint',
      designer: 'Unknown Athenian Die Engraver',
      historicalPeriod: 'Classical Greece (c. 454-404 BC)',
      rarity: RarityLevel.rare,
      authenticityConfidence: 0.96,
      authenticityReasons: [
        'Obverse displays standard high-crested helmet with three olive leaves.',
        'Incuse square reverse displays standard owl, olive sprig, and crescent moon.',
        'Weight falls correctly within Attica standard distribution of 17.15g - 17.25g.',
        'Metal analysis indicates ancient Laurion silver mines chemical signature.',
      ],
      estimatedGrade: 'Choice XF (Ch XF)',
      gradeExplanation:
          'Extremely fine details on owl features. Flann is broad and well-centered. Excellent metal quality with slight cabinet toning. Clear incuse square on the reverse.',
      frontImageUrl: 'athenian_owl_front',
      backImageUrl: 'athenian_owl_back',
      historicalInfo:
          'The Silver Tetradrachm, widely known as the "Owl," was the most influential trade coin of the Classical Greek era. Its high silver purity made it accepted worldwide, funding the construction of the Parthenon and Athenian military campaigns during the Peloponnesian Wars.',
      category: 'Ancient Coins',
      retailPrice: 4200,
      auctionPrice: 4600,
      dealerPrice: 3600,
      collectorPrice: 4100,
      minPrice: 3200,
      maxPrice: 4900,
      priceTrendPercentage: 12.2,
      investmentRating: 'A',
    ),
    CollectibleModel(
      id: 'coin_lincoln_ddo',
      type: CollectibleType.coin,
      name: '1955 Lincoln Wheat Cent (Doubled Die Obverse)',
      country: 'United States',
      year: 1955,
      denomination: '1 Cent',
      mintMark: 'None (Philadelphia)',
      composition: '95% Copper, 5% Tin/Zinc',
      weightG: 3.11,
      diameterMm: 19.0,
      thicknessMm: 1.5,
      shape: 'Round',
      edgeType: 'Plain',
      mint: 'Philadelphia Mint',
      designer: 'Victor David Brenner',
      historicalPeriod: 'Mid 20th Century',
      rarity: RarityLevel.veryRare,
      authenticityConfidence: 0.94,
      authenticityReasons: [
        'Distinct, dramatic double image visible on LIBERTY and IN GOD WE TRUST.',
        'Clear doubling on the date 1955, with the second image shifted slightly clockwise.',
        'Obverse die markers verified (specific die polish lines near Lincoln shoulder).',
      ],
      estimatedGrade: 'AU58',
      gradeExplanation:
          'Almost uncirculated with trace amounts of wear on the highest points of Lincoln\'s cheek and jaw. Retains original mint red luster near the lettering.',
      frontImageUrl: 'lincoln_ddo_front',
      backImageUrl: 'lincoln_ddo_back',
      historicalInfo:
          'One of the most famous error coins in US history, the 1955 Doubled Die Obverse occurred when a working die was misaligned during production. About 20,000 to 24,000 coins were minted and released before operators noticed, mixed into standard wheat cent shipments.',
      category: 'Error Coins',
      retailPrice: 2850,
      auctionPrice: 3100,
      dealerPrice: 2200,
      collectorPrice: 2600,
      minPrice: 1900,
      maxPrice: 3300,
      priceTrendPercentage: 9.8,
      investmentRating: 'A+',
    ),
    CollectibleModel(
      id: 'note_hamilton_1000',
      type: CollectibleType.banknote,
      name: '1918 \$1,000 Federal Reserve Note (Alexander Hamilton)',
      country: 'United States',
      year: 1918,
      denomination: '\$1,000',
      mintMark: 'Series of 1918 (New York)',
      composition: 'Cotton-Linen Paper Blend',
      weightG: 1.1,
      diameterMm: 189.0, // length
      thicknessMm: 0.12,
      shape: 'Rectangular',
      edgeType: 'Fine Cut',
      mint: 'Bureau of Engraving and Printing',
      designer: 'BEP Master Engravers',
      historicalPeriod: 'Early 20th Century (Federal Reserve Era)',
      rarity: RarityLevel.extremelyRare,
      authenticityConfidence: 0.97,
      authenticityReasons: [
        'Engravings display high fidelity with razor-sharp microprinting details.',
        'Blue seal and serial numbers show authentic ink bleed typical of 1918 flat-plate printing.',
        'Paper stock displays correct red and blue security threads embedded natively.',
        'Governor signature matches registered historical plate archives.',
      ],
      estimatedGrade: 'Choice VF35',
      gradeExplanation:
          'Very fine banknote. Clean and crisp paper structure. Three vertical folds visible under backlighting, but paper color remains vibrant. No pinholes, tears, or soil marks.',
      frontImageUrl: 'hamilton_1000_front',
      backImageUrl: 'hamilton_1000_back',
      historicalInfo:
          'High-denomination currency notes were primarily used for high-value bank-to-bank settlements. The 1918 Series featured Alexander Hamilton on the obverse, and a soaring American eagle on the reverse. Today, very few remain in private hands, with most having been redeemed and destroyed by the Treasury.',
      category: 'Bank Notes',
      retailPrice: 135000,
      auctionPrice: 155000,
      dealerPrice: 110000,
      collectorPrice: 130000,
      minPrice: 100000,
      maxPrice: 165000,
      priceTrendPercentage: 14.5,
      investmentRating: 'AA',
      governorSignature: 'Benjamin Strong / William P. G. Harding',
      serialNumber: 'B18429A',
      watermarkDescription: 'Treasury Seal Outline (Light)',
      securityThreadDescription: 'Red and Blue Silk Fiber Strands',
    ),
    CollectibleModel(
      id: 'coin_morgan_cc',
      type: CollectibleType.coin,
      name: '1882-CC Morgan Silver Dollar',
      country: 'United States',
      year: 1882,
      denomination: '\$1',
      mintMark: 'CC (Carson City)',
      composition: '90% Silver, 10% Copper',
      weightG: 26.73,
      diameterMm: 38.1,
      thicknessMm: 2.4,
      shape: 'Round',
      edgeType: 'Reeded',
      mint: 'Carson City Mint',
      designer: 'George T. Morgan',
      historicalPeriod: 'Late 19th Century (Gilded Age)',
      rarity: RarityLevel.uncommon,
      authenticityConfidence: 0.98,
      authenticityReasons: [
        'CC mint mark displays perfect alignment and size matching 1882 dies.',
        'Denticles around the rim are fully sharp and complete.',
        'Specific silver alloy density matches original specifications.',
      ],
      estimatedGrade: 'MS65',
      gradeExplanation:
          'Mint State 65. Features an incredibly strong Carson City strike with booming original luster. Barely noticeable contact marks on the cheek of Liberty. Reverse is virtually flawless.',
      frontImageUrl: 'morgan_cc_front',
      backImageUrl: 'morgan_cc_back',
      historicalInfo:
          'Minted in the legendary frontier city of Carson City, Nevada, using silver from the Comstock Lode. Morgan silver dollars from CC are highly coveted due to their association with the Wild West and lower mintages compared to Philadelphia and New Orleans.',
      category: 'Silver Coins',
      retailPrice: 650,
      auctionPrice: 720,
      dealerPrice: 520,
      collectorPrice: 610,
      minPrice: 480,
      maxPrice: 780,
      priceTrendPercentage: 6.4,
      investmentRating: 'B+',
    ),
  ];

  static List<CollectibleModel> getFeaturedCollectibles() {
    return collectibles;
  }

  // Pre-configured custom portfolio list
  static final List<PortfolioItemModel> portfolio = [
    PortfolioItemModel(
      id: 'port_1',
      collectible: collectibles[4], // Morgan CC
      purchasePrice: 480,
      purchaseDate: DateTime(2025, 4, 12),
      purchaseLocation: 'Heritage Auctions',
      seller: 'Heritage Auctions Inc.',
      storageLocation: 'Bank Safe Deposit Box B-12',
      notes:
          'Acquired in a beautiful slab from NGC. Under-graded in my opinion, could potentially cross over to MS66.',
      isFavorite: true,
    ),
    PortfolioItemModel(
      id: 'port_2',
      collectible: collectibles[1], // Athenian Owl
      purchasePrice: 3800,
      purchaseDate: DateTime(2026, 1, 5),
      purchaseLocation: 'CNG Coins',
      seller: 'Classical Numismatic Group',
      storageLocation: 'Home Display Cabinet Vault',
      notes:
          'Gorgeous cabinet toning with deep blues and purples. Beautiful history.',
      isFavorite: false,
    ),
  ];

  static List<PortfolioItemModel> getPortfolioItems() {
    return portfolio;
  }

  // Pre-configured listings for marketplace
  static final List<MarketplaceListingModel> marketplace = [
    MarketplaceListingModel(
      id: 'm_1',
      collectible: collectibles[1], // Owl
      sellerName: 'Marcus Aurelius',
      sellerAvatar:
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=150',
      isSellerVerified: true,
      price: 4100,
      status: 'active',
      escrowReady: true,
      views: 342,
      offersCount: 4,
    ),
    MarketplaceListingModel(
      id: 'm_2',
      collectible: collectibles[2], // Lincoln DDO
      sellerName: 'Penny Collector LLC',
      sellerAvatar:
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=150',
      isSellerVerified: true,
      price: 2750,
      status: 'active',
      escrowReady: true,
      views: 128,
      offersCount: 1,
    ),
    MarketplaceListingModel(
      id: 'm_3',
      collectible: collectibles[4], // Morgan
      sellerName: 'Nevada Silver Co',
      sellerAvatar:
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&q=80&w=150',
      isSellerVerified: false,
      price: 630,
      status: 'active',
      escrowReady: false,
      views: 94,
      offersCount: 0,
    ),
  ];

  static List<MarketplaceListingModel> getMarketplaceListings() {
    return marketplace;
  }

  // Realistic educational articles
  static final List<LessonModel> lessons = [
    LessonModel(
      id: 'l_1',
      title: 'How to Grade Coins: The Sheldon Scale',
      category: 'Coin Basics',
      body:
          'The Sheldon Scale is a 70-point coin grading scale used by numismatists to determine the condition and value of coins. Established in 1949 by Dr. William H. Sheldon, it ranges from Poor (P-1) to Perfect Mint State (MS-70). Understanding these grades is crucial because a single grade point difference (e.g. MS64 vs MS65) can double or triple a coin\'s market value. Key visual cues include strike sharpness, luster depth, and contact marks.',
      author: 'Dr. John Numis',
      readTime: '6 min read',
      imageUrl: 'lesson_grading',
      isBookmarked: false,
    ),
    LessonModel(
      id: 'l_2',
      title: 'Detecting Counterfeit Gold Coins',
      category: 'Counterfeit Detection',
      body:
          'Counterfeit gold coins are increasingly sophisticated, but specific tests remain definitive. First, verify weight with a high-precision scale down to 0.001g. Genuine coins possess exact dimensions (diameter and thickness). Second, check the edge reeding; counterfeits often have uneven, shallow, or merged reeding lines. Third, study the surface under 10x magnification. Look for microscopic pimples or bubbles, which indicate casting rather than striking with professional minting dies.',
      author: 'Elena Rostova, Expert Authenticator',
      readTime: '8 min read',
      imageUrl: 'lesson_counterfeit',
      isBookmarked: true,
    ),
    LessonModel(
      id: 'l_3',
      title: 'Understanding Mint Errors and Varieties',
      category: 'Mint Errors',
      body:
          'A mint error is a mistake made during the manufacturing process at the mint, resulting in unique abnormalities. Popular error types include Off-Center Strikes (where the planchet is not centered under the dies), Clipped Planchets (where the coin metal blank is cut improperly), and Doubled Dies (where the die itself has a doubled design, leaving a double impression on struck coins). Error coins are highly prized by specialists due to their dramatic visual appeal and extreme rarity.',
      author: 'Arthur Vance',
      readTime: '5 min read',
      imageUrl: 'lesson_errors',
      isBookmarked: false,
    ),
  ];

  static List<LessonModel> getLessons() {
    return lessons;
  }

  // Pre-configured achievements list
  static final List<AchievementModel> achievements = [
    AchievementModel(
      id: 'ach_1',
      title: 'First Discovery',
      description: 'Scan your very first collectible coin or note.',
      badgeIcon: 'stars',
      unlockedAt: DateTime(2026, 7, 10),
      xpAwarded: 100,
    ),
    AchievementModel(
      id: 'ach_2',
      title: 'Gold Collector',
      description: 'Add a gold coin to your portfolio collection vault.',
      badgeIcon: 'military_tech',
      unlockedAt: null,
      xpAwarded: 500,
    ),
    AchievementModel(
      id: 'ach_3',
      title: 'World Explorer',
      description: 'Collect items from 5 or more different countries.',
      badgeIcon: 'public',
      unlockedAt: DateTime(2026, 7, 11),
      xpAwarded: 300,
    ),
    AchievementModel(
      id: 'ach_4',
      title: 'Ancient Historian',
      description: 'Scan or log any coin minted before the 15th Century.',
      badgeIcon: 'auto_stories',
      unlockedAt: null,
      xpAwarded: 1000,
    ),
  ];

  static List<AchievementModel> getAchievements() {
    return achievements;
  }

  /// Historical price series for charts.
  ///
  /// No historical market-price source is connected, so this always returns an
  /// empty list and the UI shows its "trend unavailable" state. Repeating the
  /// current value across 1 month / 1 year / 5 years would present an invented
  /// price history as real data.
  static List<double> getPriceHistory(
    String id,
    String duration, {
    double? baseOverride,
  }) {
    return const <double>[];
  }

  // Simulate scanning pipeline with delays and trivia
  static Future<CollectibleModel> simulateScan(int index) async {
    await Future.delayed(const Duration(milliseconds: 3000));
    // Return a random coin from the list based on index
    return collectibles[index % collectibles.length];
  }

  static CollectorProfileModel getCollectorProfile() {
    return CollectorProfileModel(
      username: 'Vaibhav Sharma',
      bio:
          'Numismatist since 2012. Passionate collector of early US gold strikes, silver crown pieces, and classical Athenian tetradrachms.',
      rankName: 'Ancient Coin Master',
      level: 12,
      globalRanking: 342,
      reputationRating: 98,
      totalScans: 142,
      isVerifiedCollector: true,
      badgeIds: const ['ach_1', 'ach_3'],
      followersCount: 524,
      followingCount: 184,
    );
  }

  static List<SeriesCompletionModel> getSeriesCompletions() {
    return [
      SeriesCompletionModel(
        id: 'ser_double_eagle',
        title: 'Saint-Gaudens Double Eagle Set',
        country: 'United States',
        totalCount: 12,
        ownedCount: 1,
        description:
            'Complete the prestigious Augustus Saint-Gaudens gold double eagle issues from 1907 to 1933.',
        targetYears: const [
          '1907',
          '1908',
          '1910',
          '1911',
          '1914',
          '1915',
          '1920',
          '1924',
          '1928',
          '1933',
        ],
      ),
      SeriesCompletionModel(
        id: 'ser_morgan_dollar',
        title: 'Morgan Silver Dollar Registry Set',
        country: 'United States',
        totalCount: 24,
        ownedCount: 1,
        description:
            'Amass the iconic Gilded Age silver dollars minted at Philadelphia, San Francisco, and Carson City.',
        targetYears: const [
          '1878',
          '1880',
          '1882',
          '1884',
          '1885',
          '1890',
          '1893',
          '1895',
          '1904',
          '1921',
        ],
      ),
      SeriesCompletionModel(
        id: 'ser_athenian_owl',
        title: 'Classical Attica Silver Tetradrachms',
        country: 'Ancient Greece',
        totalCount: 5,
        ownedCount: 1,
        description:
            'Acquire high-grade variations of the historical Athenian Owl coins minted between 454 BC and 404 BC.',
        targetYears: const [
          'c. 454 BC',
          'c. 440 BC',
          'c. 420 BC',
          'c. 410 BC',
          'c. 404 BC',
        ],
      ),
    ];
  }

  static List<String> getAdvisorRecommendations() {
    return [
      "Series Upgrade: Consider bidding on the 1882-CC Morgan Silver Dollar in MS66 currently listed by Nevada Silver Co. It would upgrade your existing MS65 portfolio item.",
      "Diversification Tip: Your vault is heavily weighted in Silver (84%) and US issues. Acquiring an Ancient Roman Aureus or British Gold Sovereign would increase your portfolio index.",
      "Market Movement: Estimated pricing index for ancient Greek coins has appreciated by +14.2% over the last quarter. Hold your Athenian Owl Tetradrachm.",
    ];
  }
}
