//
//  CKGalleryViewManager.m
//  ReactNativeCameraKit
//
//  Created by Ran Greenberg on 20/06/2016.
//  Copyright © 2016 Wix. All rights reserved.
//

@import Photos;

#import "CKGalleryViewManager.h"
#import "CKGalleryCollectionViewCell.h"
#import "CKGalleryCustomCollectionViewCell.h"
#import "NoImageFoundCellCollectionViewCell.h"
#import "GalleryData.h"
#import "CKGalleryManager.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "CKCamera.h"

#define SCREEN_WIDTH ([[UIScreen mainScreen] bounds].size.width)
#define SCREEN_HEIGHT ([[UIScreen mainScreen] bounds].size.height)

#define DEFAULT_MINIMUM_INTERITEM_SPACING               10.0
#define DEFAULT_MINIMUM_LINE_SPACING                    10.0
#define IMAGE_SIZE_MULTIPLIER                           2



typedef void (^CompletionBlock)(BOOL success);


@interface CKGalleryView : UIView <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource>

//props
@property (nonatomic, strong) NSString *albumName;
@property (nonatomic, strong) NSNumber *minimumLineSpacing;
@property (nonatomic, strong) NSNumber *minimumInteritemSpacing;
@property (nonatomic, strong) NSNumber *columnCount;
@property (nonatomic, strong) NSNumber *getUrlOnTapImage;
@property (nonatomic, strong) NSNumber *autoSyncSelection;
@property (nonatomic, strong) NSString *imageQualityOnTap;
@property (nonatomic, copy) RCTDirectEventBlock onTapImage;
@property (nonatomic, copy) RCTDirectEventBlock onRemoteDownloadChanged;


@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) GalleryData *galleryData;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic) CGSize cellSize;
@property (nonatomic, strong) NSMutableArray *selectedImages;

@property (nonatomic, strong) PHImageRequestOptions *imageRequestOptions;

@property (nonatomic, strong) PHFetchOptions *fetchOptions;
@property (nonatomic, strong) NSString *selectedBase64Image;
@property (nonatomic, strong) UIImage *selectedImageIcon;
@property (nonatomic, strong) UIImage *unSelectedImageIcon;
@property (nonatomic, strong) UIColor *imageStrokeColor;
@property (nonatomic, strong) NSNumber *disableSelectionIcons;
@property (nonatomic, strong) NSDictionary *selection;
@property (nonatomic)         UIEdgeInsets contentInset;
@property (nonatomic)         BOOL alwaysBounce;
@property (nonatomic, strong) UIColor *remoteDownloadIndicatorColor;
@property (nonatomic, strong) NSString *remoteDownloadIndicatorType;
@property (nonatomic, strong) NSNumber *iCloudDownloadSimulateTime;
@property (nonatomic, strong) NSTimer *iCloudDownloadSimulateTimer;
@property (nonatomic) CFAbsoluteTime timePassed;

//custom button props
@property (nonatomic, strong) NSDictionary *customButtonStyle;
@property (nonatomic, copy) RCTDirectEventBlock onCustomButtonPress;

//supported props
@property (nonatomic, strong) NSDictionary *fileTypeSupport;
@property (nonatomic, strong) NSArray *supportedFileTypesArray;

@end

static NSString * const CellReuseIdentifier = @"Cell";
static NSString * const CustomCellReuseIdentifier = @"CustomCell";
static NSString * const NoimageCellReuseIdentifier = @"NoimageCell";

@implementation CKGalleryView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        
        self.selectedImages = [[NSMutableArray alloc] init];
        self.imageManager = [[PHCachingImageManager alloc] init];
        
        self.imageRequestOptions = [[PHImageRequestOptions alloc] init];
        self.imageRequestOptions.synchronous = YES;
        
        self.contentInset = UIEdgeInsetsZero;
    }
    
    return self;
}


-(CGSize)cellSize {
    if(self.galleryData.data.count == 0) {
        return self.bounds.size;
    }
    if (CGSizeEqualToSize(_cellSize, CGSizeZero)) {
        CGFloat minSize = (MAX(self.bounds.size.width - ((self.columnCount.floatValue-1.0f)*self.minimumInteritemSpacing.floatValue),0))/self.columnCount.floatValue;
        _cellSize = CGSizeMake(minSize, minSize);
    }
    return _cellSize;
}

-(PHFetchOptions *)fetchOptions {
    if (!_fetchOptions) {
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d",PHAssetMediaTypeImage];
        
        _fetchOptions = fetchOptions;
    }
    
    return _fetchOptions;
}


-(void)removeFromSuperview {
    [CKGalleryCollectionViewCell cleanStaticsVariables];
    [super removeFromSuperview];
}


-(void)reactSetFrame:(CGRect)frame {
    [super reactSetFrame:frame];
    
    if (CGRectIsEmpty(frame)) return;
    
    if (!self.collectionView) {
        UICollectionViewFlowLayout* flowLayout = [[UICollectionViewFlowLayout alloc] init];
        flowLayout.itemSize = self.cellSize;
        [flowLayout setScrollDirection:UICollectionViewScrollDirectionVertical];
        
        self.collectionView = [[UICollectionView alloc] initWithFrame:self.bounds collectionViewLayout:flowLayout];
        self.collectionView.contentInset = self.contentInset;
        self.collectionView.scrollIndicatorInsets = self.contentInset;
        self.collectionView.alwaysBounceVertical = self.alwaysBounce;
        self.collectionView.delegate = self;
        self.collectionView.dataSource = self;
        
        [self.collectionView registerClass:[CKGalleryCollectionViewCell class] forCellWithReuseIdentifier:CellReuseIdentifier];
        [self.collectionView registerClass:[CKGalleryCustomCollectionViewCell class] forCellWithReuseIdentifier:CustomCellReuseIdentifier];
        [self.collectionView registerClass:[NoImageFoundCellCollectionViewCell class] forCellWithReuseIdentifier:NoimageCellReuseIdentifier];
        [self addSubview:self.collectionView];
        self.collectionView.backgroundColor = [UIColor blackColor];
    }
    else {
        self.collectionView.frame = self.bounds;
    }
    
}

#pragma mark - Collection view layout things


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.cellSize;
}


- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return self.minimumInteritemSpacing ? self.minimumInteritemSpacing.floatValue : DEFAULT_MINIMUM_INTERITEM_SPACING;
}


- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return self.minimumLineSpacing ? self.minimumLineSpacing.floatValue : DEFAULT_MINIMUM_INTERITEM_SPACING;
}

-(void)upadateCollectionView:(PHFetchResult*)fetchResults animated:(BOOL)animated {
    
    self.galleryData = [[GalleryData alloc] initWithFetchResults:fetchResults selectedImagesIds:self.selectedImages];
    
    if (animated) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ {
            [self.collectionView performBatchUpdates:^{
                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:0]];
            } completion:nil];
        });
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self.collectionView reloadData];
        });
    }
}


-(void)setSelectedImageIcon:(UIImage *)selectedImage {
    [CKGalleryCollectionViewCell setSelectedImageIcon:selectedImage];
}


-(void)setUnSelectedImageIcon:(UIImage *)unSelectedImage {
    [CKGalleryCollectionViewCell setUnSlectedImageIcon:unSelectedImage];
}

-(void)setImageStrokeColor:(UIColor *)imageStrokeColor {
    [CKGalleryCollectionViewCell setImageStrokeColor:imageStrokeColor];
}

-(void)setSelection:(NSDictionary *)selection {
    [CKGalleryCollectionViewCell setSelection:selection];
}

-(void)setContentInset:(UIEdgeInsets)contentInset {
    if(self.collectionView) {
        self.collectionView.contentInset = contentInset;
    }
    _contentInset = contentInset;
}

-(void)setRemoteDownloadIndicatorColor:(UIColor *)remoteDownloadIndicatorColor {
    [CKGalleryCollectionViewCell setRemoteDownloadIndicatorColor:remoteDownloadIndicatorColor];
}

-(void)setRemoteDownloadIndicatorType:(NSString *)remoteDownloadIndicatorType {
    [CKGalleryCollectionViewCell setRemoteDownloadIndicatorType:remoteDownloadIndicatorType];
}

-(void)setAlwaysBounce:(BOOL)alwaysBounce {
    if(self.collectionView) {
        self.collectionView.alwaysBounceVertical = alwaysBounce;
    }
    _alwaysBounce = alwaysBounce;
}

-(void)setFileTypeSupport:(NSDictionary *)supported {
    _fileTypeSupport = supported;
    
    NSMutableDictionary *supportedDict = [[NSMutableDictionary alloc] init];
    
    // SUPPORTED_FILE_TYPES
    id supportedFileTypesId = self.fileTypeSupport[SUPPORTED_FILE_TYPES];
    if (supportedFileTypesId) {
        NSArray *supportedFileTypesArray = [RCTConvert NSArray:supportedFileTypesId];
        supportedDict[SUPPORTED_FILE_TYPES] = supportedFileTypesArray;
        
        self.supportedFileTypesArray = [NSArray arrayWithArray:supportedFileTypesArray];
    }
    
    // UNSUPPORTED_OVERLAY_COLOR
    id unsupportedOverlayColorId = self.fileTypeSupport[UNSUPPORTED_OVERLAY_COLOR];
    if (unsupportedOverlayColorId) {
        UIColor *unsupportedOverlayColor = [RCTConvert UIColor:unsupportedOverlayColorId];
        supportedDict[UNSUPPORTED_OVERLAY_COLOR] = unsupportedOverlayColor;
    }
    
    // UNSUPPORTED_OVERLAY_COLOR
    id unsupportedImageId = self.fileTypeSupport[UNSUPPORTED_IMAGE];
    if (unsupportedImageId) {
        UIImage *unsupportedImage = [RCTConvert UIImage:unsupportedImageId];
        supportedDict[UNSUPPORTED_IMAGE] = unsupportedImage;
    }
    
    // UNSUPPORTED_TEXT
    id unsupportedTextId = self.fileTypeSupport[UNSUPPORTED_TEXT];
    if (unsupportedTextId) {
        NSString *unsupportedText = [RCTConvert NSString:unsupportedTextId];
        supportedDict[UNSUPPORTED_TEXT] = unsupportedText;
    }
    
    // UNSUPPORTED_TEXT_COLOR
    id unsupportedTextColorId = self.fileTypeSupport[UNSUPPORTED_TEXT_COLOR];
    if (unsupportedTextColorId) {
        UIColor *unsupportedTextColor = [RCTConvert UIColor:unsupportedTextColorId];
        supportedDict[UNSUPPORTED_TEXT_COLOR] = unsupportedTextColor;
    }
    
    [CKGalleryCollectionViewCell setSupported:supportedDict];
}


-(void)setAlbumName:(NSString *)albumName {
    
    
//    if ([albumName caseInsensitiveCompare:@"all photos"] == NSOrderedSame || !albumName || [albumName isEqualToString:@""]) {
//
//        PHFetchResult *allPhotosFetchResults = [PHAsset fetchAssetsWithOptions:self.fetchOptions];
//        [self upadateCollectionView:allPhotosFetchResults animated:(self.galleryData != nil)];
//        return;
//    }
    
    PHFetchResult *collections = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    
    [smartAlbums enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSLog(@"%@", collection.localizedTitle);
        if ([collection.localizedTitle isEqualToString:albumName]) {
            
            PHFetchResult *collectionFetchResults = [PHAsset fetchAssetsInAssetCollection:collection options:nil];
            [self upadateCollectionView:collectionFetchResults animated:(self.galleryData != nil)];
            *stop = YES;
            return;
        }
    }];
    
}


#pragma mark - UICollectionViewDataSource


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSUInteger itemsAmount = self.galleryData.data.count;
    if (self.customButtonStyle) {
        itemsAmount++;
    }
    if (itemsAmount == 0) {
        return 1;
    }
    return itemsAmount;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    NSInteger cellIndex = indexPath.row;
    if(self.galleryData.data.count == 0) {
        NoImageFoundCellCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:NoimageCellReuseIdentifier forIndexPath:indexPath];
        [cell setView];
        return cell;
    }
    if (self.customButtonStyle ) {
        cellIndex--;
        
        if (indexPath.row == 0) {
            CKGalleryCustomCollectionViewCell *customCell = [collectionView dequeueReusableCellWithReuseIdentifier:CustomCellReuseIdentifier forIndexPath:indexPath];
            [customCell applyStyle:self.customButtonStyle];
            return customCell;
        }
        
    }
    
    NSDictionary *assetDictionary = (NSDictionary*)self.galleryData.data[cellIndex];
    PHAsset *asset = assetDictionary[@"asset"];
    
    NSString *fileType = [self extractFileTypeForAsset:asset];
    
    CFStringRef fileExtension = (__bridge CFStringRef)[fileType pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    NSString *MIMETypeString = (__bridge_transfer NSString *)MIMEType;
    
    __block CKGalleryCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CellReuseIdentifier forIndexPath:indexPath];
    cell.disableSelectionIcons = self.disableSelectionIcons ? self.disableSelectionIcons.boolValue : false;
    
    if (self.supportedFileTypesArray) {
        cell.isSupported = [self.supportedFileTypesArray containsObject:[MIMETypeString lowercaseString]];
    }
    
    cell.representedAssetIdentifier = asset.localIdentifier;
    if ([MIMETypeString containsString:@"image"]){
        [cell.videoIcon setHidden:true];
    }else{
        [cell.videoIcon setHidden:false];
    }
    [self.imageManager requestImageForAsset:asset
                                 targetSize:CGSizeMake(self.cellSize.width*IMAGE_SIZE_MULTIPLIER, self.cellSize.height*IMAGE_SIZE_MULTIPLIER)
                                contentMode:PHImageContentModeDefault
                                    options:nil
                              resultHandler:^(UIImage *result, NSDictionary *info) {
                                  
                                  if ([cell.representedAssetIdentifier isEqualToString:asset.localIdentifier]) {
                                      cell.thumbnailImage = result;
                                  }
                              }];
    
    return cell;
}


-(void)remoteDownloadingUpdate:(CKGalleryCollectionViewCell *)cell progress:(CGFloat)progress isDownloading:(BOOL)isDownloading {
    if (cell.isDownloading != isDownloading) {
        if (self.onRemoteDownloadChanged) {
            self.onRemoteDownloadChanged(@{@"isRemoteDownloading": [NSNumber numberWithBool:isDownloading]});
        }
    }
    cell.isDownloading = isDownloading;
    cell.downloadingProgress = progress;
}


-(NSString*)extractFileTypeForAsset:(PHAsset*)asset {
    return [asset valueForKey:@"uniformTypeIdentifier"];
}

-(void)downloadImageFromICloud:(PHAsset *)asset cell:(CKGalleryCollectionViewCell *)cell completion:(CompletionBlock)completion {
    
    PHImageManager *manager = [PHImageManager defaultManager];
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.synchronous = NO;
    [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self remoteDownloadingUpdate:cell progress:progress isDownloading:YES];
        });
    }];
    
    [manager
     requestImageDataForAsset:asset
     options:options
     resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
         
         if (imageData) {
             dispatch_async(dispatch_get_main_queue(), ^{
                 [self remoteDownloadingUpdate:cell progress:1 isDownloading:NO];
                 
                 if (completion) {
                     completion(YES);
                 }
             });
         }
         else {
             dispatch_async(dispatch_get_main_queue(), ^{
                 [self remoteDownloadingUpdate:cell progress:0 isDownloading:NO];
                 if (completion) {
                     completion(NO);
                 }
             });
         }
         
     }];
    
}


-(void)simulateICloudDownload:(NSTimer *)timer {
    CKGalleryCollectionViewCell *cell = (CKGalleryCollectionViewCell *)timer.userInfo[@"cell"];
    CFAbsoluteTime currentTimePassed = CFAbsoluteTimeGetCurrent() - self.timePassed;
    
    if (currentTimePassed <= [self.iCloudDownloadSimulateTime doubleValue]) {
        
        [self remoteDownloadingUpdate:cell
                             progress:currentTimePassed/[self.iCloudDownloadSimulateTime doubleValue]
                        isDownloading:YES];
        
    }
    else {
        CompletionBlock completion = (CompletionBlock)timer.userInfo[@"completion"];
        
        [self.iCloudDownloadSimulateTimer invalidate];
        self.iCloudDownloadSimulateTimer = nil;
        [self remoteDownloadingUpdate:cell
                             progress:1
                        isDownloading:NO];
        
        if (completion) {
            completion(YES);
        }
    }
}

-(void)downloadImageFromICloudIfNeeded:(PHAsset *)asset cell:(CKGalleryCollectionViewCell *)cell completion:(CompletionBlock)completion {
    
    if (self.iCloudDownloadSimulateTime && !cell.isSelected) {
        self.timePassed = CFAbsoluteTimeGetCurrent();
        
        self.iCloudDownloadSimulateTimer = [NSTimer scheduledTimerWithTimeInterval:[self.iCloudDownloadSimulateTime doubleValue]/100
                                                                            target:self
                                                                          selector:@selector(simulateICloudDownload:)
                                                                          userInfo:@{@"cell": cell, @"completion": completion}
                                                                           repeats:YES];
        
        return;
    }
    
    
    PHImageManager *manager = [PHImageManager defaultManager];
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = NO;
    options.synchronous = YES;
    
    [manager
     requestImageDataForAsset:asset
     options:options
     resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
         
         if ([[info valueForKey:PHImageResultIsInCloudKey] boolValue]) {
             dispatch_async(dispatch_get_main_queue(), ^{
                 [self remoteDownloadingUpdate:cell progress:0 isDownloading:YES];
                 [self downloadImageFromICloud:asset cell:cell completion:completion];
             });
         }
         else {
             dispatch_async(dispatch_get_main_queue(), ^{
                 if (completion) {
                     completion(YES);
                 }
             });
         }
     }];
}


#pragma mark - UICollectionViewDelegate


- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    
    NSInteger galleryDataIndex = indexPath.row;
    if (self.customButtonStyle) {
        galleryDataIndex--;
    }
    
    if (indexPath.row == 0 && self.onCustomButtonPress) {
        self.onCustomButtonPress(@{@"selected":@"customButtonPressed"});
        return;
    }
    
    id selectedCell =[collectionView cellForItemAtIndexPath:indexPath];
    
    if ([selectedCell isKindOfClass:[CKGalleryCollectionViewCell class]]) {
        CKGalleryCollectionViewCell *ckCell = (CKGalleryCollectionViewCell*)selectedCell;
        
        NSMutableDictionary *assetDictionary = (NSMutableDictionary*)self.galleryData.data[galleryDataIndex];
        PHAsset *asset = assetDictionary[@"asset"];
        NSNumber *isSelectedNumber = assetDictionary[@"isSelected"];
        assetDictionary[@"isSelected"] = [NSNumber numberWithBool:!(isSelectedNumber.boolValue)];
        
        [self downloadImageFromICloudIfNeeded:asset cell:ckCell completion:^(BOOL success) {
            
            if (success) {
                if (!ckCell.isSupported) {
                    return;
                }
                
                ckCell.isSelected = !ckCell.isSelected;
                
                [self onSelectChanged:asset isSelected:ckCell.isSelected];
            }
        }];
    }
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if([cell isKindOfClass:[CKGalleryCollectionViewCell class]]) {
        CKGalleryCollectionViewCell *ckCell = (CKGalleryCollectionViewCell*)cell;
        
        NSInteger galleryDataIndex = indexPath.row;
        if (self.customButtonStyle) {
            galleryDataIndex--;
        }
        NSDictionary *assetDictionary = (NSDictionary*)self.galleryData.data[galleryDataIndex];
        ckCell.isSelected = ((NSNumber*)assetDictionary[@"isSelected"]).boolValue;
    }
}

-(BOOL)isSelectionDirty:(NSMutableArray *)newSelectedImages {
    if(![self.autoSyncSelection boolValue]) {
        return NO;
    }
    NSArray *mergedArray = [newSelectedImages arrayByAddingObjectsFromArray:self.selectedImages];
    NSArray *arrayWithoutDuplicates = [[NSOrderedSet orderedSetWithArray:mergedArray] array];
    return (arrayWithoutDuplicates.count > 0);
}

-(void)setSelectedImages:(NSMutableArray *)selectedImages {
    BOOL selectionDirty = [self isSelectionDirty:selectedImages];
    if (selectedImages) {
        _selectedImages = selectedImages;
    }
    
    if(selectionDirty && [self.autoSyncSelection boolValue]) {
        //sync visible cells
        for (CKGalleryCollectionViewCell *cell in [self.collectionView visibleCells]) {
            if([cell respondsToSelector:@selector(representedAssetIdentifier)]) {
                cell.isSelected = ([selectedImages indexOfObject:cell.representedAssetIdentifier] != NSNotFound);
            }
        }
        //sync data
        for (NSMutableDictionary *dataDic in self.galleryData.data) {
            PHAsset *asset = dataDic[@"asset"];
            dataDic[@"isSelected"] = @([selectedImages indexOfObject:asset.localIdentifier] != NSNotFound);
        }
    }
}


-(void)refreshGalleryView:(NSArray*)selectedImages {
    self.selectedImages = [NSMutableArray arrayWithArray:selectedImages];
    [self setAlbumName:self.albumName];
}


#pragma mark - misc


-(void)onSelectChanged:(PHAsset*)asset isSelected:(BOOL)isSelected{
    if (self.onTapImage) {
        
        NSMutableDictionary *imageTapInfo = [@{@"width": [NSNumber numberWithUnsignedInteger:asset.pixelWidth],
                                               @"height": [NSNumber numberWithUnsignedInteger:asset.pixelHeight]} mutableCopy];
        
        BOOL shouldReturnUrl = self.getUrlOnTapImage ? [self.getUrlOnTapImage boolValue] : NO;
        NSNumber *isSelectedNumber = [NSNumber numberWithBool:isSelected];
        if (shouldReturnUrl) {
            PHImageRequestOptions *imageRequestOptions = [[PHImageRequestOptions alloc] init];
            imageRequestOptions.synchronous = YES;
            [CKGalleryViewManager infoForAsset:asset imageRequestOptions:imageRequestOptions imageQuality:self.imageQualityOnTap assetsInfo:^(NSMutableDictionary *dic) {
                NSString *uriString = dic[@"uri"];
                
                if (uriString) {
                    [imageTapInfo addEntriesFromDictionary:@{@"selected": uriString, @"selectedId": asset.localIdentifier, @"isSelected": isSelectedNumber}];
                    self.onTapImage(imageTapInfo);
                }
                else {
                    self.onTapImage(@{@"Error": @"Could not get image uri"});
                }
            }];
            
        }
        else {
            [imageTapInfo addEntriesFromDictionary:@{@"selected":asset.localIdentifier, @"isSelected": isSelectedNumber}];
            self.onTapImage(imageTapInfo);
        }
    }
}


+(PHFetchResult*)filterFetchResults:(PHFetchResult*)fetchResults typesArray:(NSArray*)typesArray {
    
    [fetchResults enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSLog(@"obj");
    }];
    
    return nil;
    
}


@end

@interface CKGalleryViewManager ()

@property (nonatomic, strong) CKGalleryView *galleryView;

@end


@implementation CKGalleryViewManager


RCT_EXPORT_MODULE()


- (UIView *)view
{
    self.galleryView = [[CKGalleryView alloc] init];
    return self.galleryView;
}


RCT_EXPORT_VIEW_PROPERTY(albumName, NSString);
RCT_EXPORT_VIEW_PROPERTY(minimumLineSpacing, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(minimumInteritemSpacing, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(columnCount, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(onTapImage, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(selectedImageIcon, UIImage);
RCT_EXPORT_VIEW_PROPERTY(unSelectedImageIcon, UIImage);
RCT_EXPORT_VIEW_PROPERTY(selectedImages, NSArray);
RCT_EXPORT_VIEW_PROPERTY(fileTypeSupport, NSDictionary);
RCT_EXPORT_VIEW_PROPERTY(imageStrokeColor, UIColor);
RCT_EXPORT_VIEW_PROPERTY(disableSelectionIcons, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(customButtonStyle, NSDictionary);
RCT_EXPORT_VIEW_PROPERTY(onCustomButtonPress, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(getUrlOnTapImage, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(autoSyncSelection, NSNumber);
RCT_EXPORT_VIEW_PROPERTY(selection, NSDictionary);
RCT_EXPORT_VIEW_PROPERTY(contentInset, UIEdgeInsets);
RCT_EXPORT_VIEW_PROPERTY(imageQualityOnTap, NSString);
RCT_EXPORT_VIEW_PROPERTY(alwaysBounce, BOOL);
RCT_EXPORT_VIEW_PROPERTY(remoteDownloadIndicatorColor, UIColor);
RCT_EXPORT_VIEW_PROPERTY(remoteDownloadIndicatorType, NSString);
RCT_EXPORT_VIEW_PROPERTY(onRemoteDownloadChanged, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(iCloudDownloadSimulateTime, NSNumber);

//[[GalleryData alloc] initWithFetchResults:fetchResults selectedImagesIds:self.selectedImages];


RCT_EXPORT_METHOD(getSelectedImages:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    NSError *error = nil;
    NSURL *directoryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error];
    
    NSMutableArray *assetsUrls = [[NSMutableArray alloc] init];
    
    for (PHAsset *asset in self.galleryView.selectedImages) {
        
        [self.galleryView.imageManager requestImageDataForAsset:asset options:nil resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
            
            NSURL *fileURLKey = info[@"PHImageFileURLKey"];
            if (!fileURLKey) {
                if (resolve) {
                    resolve(nil);
                }
            }
            
            NSMutableDictionary *assetInfoDict = [[NSMutableDictionary alloc] init];
            
            NSString *fileName = ((NSURL*)info[@"PHImageFileURLKey"]).lastPathComponent;
            if (fileName) {
                assetInfoDict[@"name"] = fileName;
            }
            
            float imageSize = imageData.length;
            assetInfoDict[@"size"] = [NSNumber numberWithFloat:imageSize];
            
            NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
            NSError *error = nil;
            [imageData writeToURL:fileURL options:NSDataWritingAtomic error:&error];
            
            if (!error && fileURL) {
                assetInfoDict[@"uri"] = fileURL.absoluteString;
            }
            
            [assetsUrls addObject:assetInfoDict];
            
            if (asset == self.galleryView.selectedImages.lastObject) {
                if (resolve) {
                    resolve(@{@"selectedImages":assetsUrls});
                }
            }
        }];
    }
}


RCT_EXPORT_METHOD(refreshGalleryView:(NSArray*)selectedImages
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSMutableArray *newArray = [[NSMutableArray alloc] initWithArray:selectedImages];
    [self.galleryView refreshGalleryView:newArray];
    
    if (resolve)
        resolve(@YES);
}

RCT_EXPORT_METHOD(modifyGalleryViewContentOffset:(NSDictionary*)params) {
    CGPoint newOffset = self.galleryView.collectionView.contentOffset;
    if(params[@"x"] != nil) {
        newOffset.x += [params[@"x"] floatValue];
    }
    if(params[@"y"] != nil) {
        newOffset.y += [params[@"y"] floatValue];
    }
    [self.galleryView.collectionView setContentOffset:newOffset];
}

#pragma mark - Static functions


+(void)infoForAsset:(PHAsset*)asset
                imageRequestOptions:(PHImageRequestOptions*)imageRequestOptions
                       imageQuality:(NSString*)imageQuality
         assetsInfo:(void (^) (NSMutableDictionary *dic))handler {
    
    NSError *error = nil;
    NSURL *directoryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] isDirectory:YES];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error];
    
    if (error) {
        //NSLog(@"ERROR while creating directory:%@",error);
    }
    
    
    __block NSMutableDictionary *assetInfoDict = nil;
    assetInfoDict = [[NSMutableDictionary alloc] init];
    if (asset.mediaType == PHAssetMediaTypeVideo)  {
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:nil resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info)
             {
                 if ([asset isKindOfClass:[AVURLAsset class]])
                 {
                     
                     assetInfoDict = [[NSMutableDictionary alloc] init];
                     NSURL *url = [(AVURLAsset*)asset URL];
                     NSLog(@"%@", url);
                     NSString * fileName =  url.lastPathComponent;
                     if (fileName) {
                         assetInfoDict[@"name"] = fileName;
                     }
                     NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
                     NSError *error = nil;
                     NSData *videoData = [NSData dataWithContentsOfURL:url];
                     [videoData writeToURL:fileURL options:NSDataWritingAtomic error:&error];
                     if (!error && fileURL) {
                         assetInfoDict[@"uri"] = fileURL.absoluteString;
                     }
                     else if (error){
                         //NSLog(@"%@", error);
                     }
            
                     float imageSize = 2;
                     assetInfoDict[@"size"] = [NSNumber numberWithFloat:imageSize];
                     assetInfoDict[@"width"] = [NSNumber numberWithFloat:3];
                     assetInfoDict[@"height"] = [NSNumber numberWithFloat:3];
                     assetInfoDict[@"mediaType"] = @"video";
                     handler(assetInfoDict);
                     // do what you want with it
                 }
             }];
            
        });
        
    }
    if (asset.mediaType == PHAssetMediaTypeImage) {
        [[PHCachingImageManager defaultManager] requestImageDataForAsset:asset options:imageRequestOptions resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
            
            NSData *compressedImageData = imageData;
            UIImage *compressedImage = [UIImage imageWithData:imageData];
            
            NSURL *fileURLKey = info[@"PHImageFileURLKey"];
            
            if (fileURLKey) {
            
                assetInfoDict[@"width"] = [NSNumber numberWithFloat:compressedImage.size.width];
                assetInfoDict[@"height"] = [NSNumber numberWithFloat:compressedImage.size.height];
                assetInfoDict[@"mediaType"] = @"image";

                NSString *fileName = ((NSURL*)info[@"PHImageFileURLKey"]).lastPathComponent;
                if (fileName) {
                    assetInfoDict[@"name"] = fileName;
                } else {
                    fileName = @"";
                }
                
                float imageSize = 0;
                if (compressedImageData) {
                    imageSize = compressedImageData.length;
                }
                assetInfoDict[@"size"] = [NSNumber numberWithFloat:imageSize];
                
                NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
                NSError *error = nil;
                
                [compressedImageData writeToURL:fileURL options:NSDataWritingAtomic error:&error];
                
                if (!error && fileURL) {
                    assetInfoDict[@"uri"] = fileURL.absoluteString;
                }
                else if (error){
                    //NSLog(@"%@", error);
                }
                handler(assetInfoDict);
            }
        }];
    }
    
    if (assetInfoDict && asset) {
        assetInfoDict[@"asset"] = asset;
    }
}




@end
