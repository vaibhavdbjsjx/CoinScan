import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../../core/network/mock_api.dart';
import '../../core/storage/models.dart';
import '../../core/theme/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Local state for toggles and bookmarks
  bool _biometricsEnabled = true;
  bool _cloudSyncEnabled = true;
  String _currency = 'USD';
  List<LessonModel> _lessonsList = [];
  List<AchievementModel> _achievementsList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _lessonsList = MockApi.getLessons();
    _achievementsList = MockApi.getAchievements();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleBookmark(int index) {
    setState(() {
      _lessonsList[index] = _lessonsList[index].copyWith(
        isBookmarked: !_lessonsList[index].isBookmarked,
      );
    });
    
    final isBookmarked = _lessonsList[index].isBookmarked;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isBookmarked ? AppColors.emerald : AppColors.crimson,
        content: Text(
          isBookmarked ? 'Article bookmarked for offline reading.' : 'Article removed from bookmarks.',
          style: AppTypography.buttonText,
        ),
      ),
    );
  }

  void _showLessonReader(LessonModel lesson) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top header image area mockup
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Center(
                    child: Icon(Icons.school, size: 48, color: AppColors.goldDark),
                  ),
                ),
                
                // Content Scroll View
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              lesson.category.toUpperCase(),
                              style: AppTypography.goldLabel.copyWith(fontSize: 10),
                            ),
                            Text(lesson.readTime, style: AppTypography.caption),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(lesson.title, style: AppTypography.sectionHeader.copyWith(fontSize: 22)),
                        const SizedBox(height: 8),
                        Text('By ${lesson.author}', style: AppTypography.caption),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          lesson.body,
                          style: AppTypography.bodyMedium.copyWith(height: 1.6, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Bottom dismiss
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GoldButton(
                          text: 'Finish Reading',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 1. Profile Immersive Header Block
          Stack(
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.textPrimary, Colors.black],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold,
                            ),
                            child: const CircleAvatar(
                              radius: 36,
                              backgroundColor: AppColors.goldLight,
                              child: Icon(Icons.person, size: 40, color: AppColors.goldDark),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Vaibhav Sharma',
                                    style: AppTypography.sectionHeader.copyWith(color: Colors.white, fontSize: 20),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified, color: AppColors.gold, size: 18),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Member since July 2026 • LVL 12',
                                style: AppTypography.caption.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Tab Bar selections
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.goldDark,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              tabs: const [
                Tab(text: 'Showcase'),
                Tab(text: 'Achievements'),
                Tab(text: 'Learning Hub'),
                Tab(text: 'Settings'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: Showcase public profile
                _buildShowcaseTab(),

                // TAB 2: Achievements & Gamification list
                _buildAchievementsTab(),

                // TAB 3: Learning Hub lessons list
                _buildLearningHubTab(),

                // TAB 4: Device App Settings
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Level summary block
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('EXP POINTS', style: AppTypography.caption),
                  Text('4,500 / 5,000 XP', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 0.9,
                color: AppColors.gold,
                backgroundColor: AppColors.border,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Level 12', style: AppTypography.goldLabel),
                  Text('500 XP to Level 13', style: AppTypography.caption),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        Text('Earned Badges', style: AppTypography.sectionHeader),
        const SizedBox(height: 16),

        ...List.generate(_achievementsList.length, (idx) {
          final ach = _achievementsList[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppTheme.premiumShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ach.isUnlocked ? AppColors.gold.withOpacity(0.12) : AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ach.badgeIcon == 'stars' ? Icons.stars :
                    ach.badgeIcon == 'public' ? Icons.public :
                    ach.badgeIcon == 'military_tech' ? Icons.military_tech : Icons.menu_book,
                    color: ach.isUnlocked ? AppColors.goldDark : AppColors.textMuted,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            ach.title,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ach.isUnlocked ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                          if (ach.isUnlocked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.emeraldLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'UNLOCKED',
                                style: AppTypography.goldLabel.copyWith(fontSize: 8, color: AppColors.emerald),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(ach.description, style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
          ).animate(delay: (idx * 100).ms).slideY(begin: 0.1, end: 0).fadeIn();
        }),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildLearningHubTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _lessonsList.length,
      itemBuilder: (context, index) {
        final lesson = _lessonsList[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppTheme.premiumShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showLessonReader(lesson),
            child: Row(
              children: [
                // Lesson header banner mockup
                Container(
                  width: 90,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.gold.withOpacity(0.2), AppColors.goldLight.withOpacity(0.5)],
                    ),
                  ),
                  child: const Icon(Icons.school_outlined, color: AppColors.goldDark, size: 28),
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(lesson.category.toUpperCase(), style: AppTypography.goldLabel.copyWith(fontSize: 9)),
                            Text(lesson.readTime, style: AppTypography.caption.copyWith(fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lesson.title,
                          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('By ${lesson.author}', style: AppTypography.caption.copyWith(fontSize: 10)),
                            GestureDetector(
                              onTap: () => _toggleBookmark(index),
                              child: Icon(
                                lesson.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                                color: AppColors.goldDark,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('App Preferences', style: AppTypography.sectionHeader),
        const SizedBox(height: 16),
        
        // Currency Selector
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          title: Text('Preferred Currency', style: AppTypography.bodyMedium),
          trailing: DropdownButton<String>(
            value: _currency,
            underline: const SizedBox(),
            items: ['USD', 'EUR', 'GBP', 'CAD'].map((cur) {
              return DropdownMenuItem(
                value: cur,
                child: Text(cur, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _currency = val;
                });
              }
            },
          ),
        ),
        
        const SizedBox(height: 24),
        Text('Security & Sync', style: AppTypography.sectionHeader),
        const SizedBox(height: 16),

        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          activeColor: AppColors.gold,
          title: Text('Biometric Authentication', style: AppTypography.bodyMedium),
          subtitle: Text('Lock vault catalog items with Face ID', style: AppTypography.caption),
          value: _biometricsEnabled,
          onChanged: (val) {
            setState(() {
              _biometricsEnabled = val;
            });
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          activeColor: AppColors.gold,
          title: Text('Real-time Cloud Backups', style: AppTypography.bodyMedium),
          subtitle: Text('Sync portfolios encrypted across devices', style: AppTypography.caption),
          value: _cloudSyncEnabled,
          onChanged: (val) {
            setState(() {
              _cloudSyncEnabled = val;
            });
          },
        ),

        const SizedBox(height: 24),
        Text('Data Export', style: AppTypography.sectionHeader),
        const SizedBox(height: 16),

        // CSV Export button
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          leading: Icon(Icons.download_for_offline_outlined, color: AppColors.goldDark),
          title: Text('Export Portfolio (CSV)', style: AppTypography.bodyMedium),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.emerald,
                content: Text(
                  'CSV Portfolio sheet compiled and downloaded.',
                  style: AppTypography.buttonText,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: AppColors.surface,
          leading: const Icon(Icons.delete_outline, color: AppColors.crimson),
          title: Text('Delete Account', style: AppTypography.bodyMedium.copyWith(color: AppColors.crimson)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () {
            // Mock delete prompt
            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('Delete Vault Account?'),
                  content: const Text('This action is permanent. All backing backups will be deleted from secure cloud storage.'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    TextButton(
                      child: const Text('Delete', style: TextStyle(color: AppColors.crimson)),
                      onPressed: () {
                        Navigator.pop(context);
                        // Mock exit or clear
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildShowcaseTab() {
    final profile = MockApi.getCollectorProfile();
    final items = MockApi.getPortfolioItems();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Premium Showcase Card
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.goldLight,
                    radius: 28,
                    child: Text(
                      profile.username.substring(0, 1),
                      style: AppTypography.heroTitle.copyWith(fontSize: 24, color: AppColors.goldDark),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              profile.username,
                              style: AppTypography.sectionHeader.copyWith(fontSize: 18),
                            ),
                            if (profile.isVerifiedCollector) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, color: AppColors.gold, size: 16),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              profile.rankName,
                              style: AppTypography.goldLabel.copyWith(fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            const PremiumBadge(size: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                profile.bio,
                style: AppTypography.bodyMuted.copyWith(height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 20),
              
              // Statistics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildShowcaseStat('Global Rank', '#${profile.globalRanking}'),
                  _buildShowcaseStat('Reputation', '${profile.reputationRating}%'),
                  _buildShowcaseStat('Scans', '${profile.totalScans}'),
                  _buildShowcaseStat('Level', '${profile.level}'),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Family Shared Vaults section
        Text('Family Shared Vaults', style: AppTypography.sectionHeader),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt_outlined, color: AppColors.goldDark, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Family Trust Vault',
                        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'ACTIVE SYNC',
                      style: AppTypography.goldLabel.copyWith(fontSize: 8, color: AppColors.emerald),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Members list & permissions:',
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildFamilyMemberRow('Dad (Owner)', 'Viewer permissions'),
              _buildFamilyMemberRow('Vaibhav Sharma (You)', 'Admin permissions'),
              _buildFamilyMemberRow('Brother (Viewer)', 'Viewer permissions'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 0.72,
                color: AppColors.emerald,
                backgroundColor: AppColors.border,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Text('Shared Wishlist Progress: 18 / 25 items collected', style: AppTypography.caption.copyWith(fontSize: 10)),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Public Collection Showcase list
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Public Showcase Grid', style: AppTypography.sectionHeader),
            Text('${items.length} items', style: AppTypography.caption),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final c = items[index].collectible;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        c.type == CollectibleType.coin ? Icons.monetization_on : Icons.bookmark,
                        color: AppColors.gold,
                        size: 20,
                      ),
                      Text(
                        'NGC MS${c.estimatedGrade}',
                        style: AppTypography.goldLabel.copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                  Text(
                    c.name,
                    style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '\$${c.retailPrice.toStringAsFixed(0)} Est.',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.emerald),
                  ),
                ],
              ),
            );
          },
        ),
        
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildShowcaseStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: AppTypography.sectionHeader.copyWith(fontSize: 16, color: AppColors.goldDark)),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption.copyWith(fontSize: 10)),
      ],
    );
  }

  Widget _buildFamilyMemberRow(String name, String role) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: AppTypography.bodyMedium.copyWith(fontSize: 12)),
          Text(role, style: AppTypography.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
