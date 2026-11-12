import SwiftUI
import AVFoundation
import CoreLocation
import AppIntents

// 1. Full-Length Dual Background Audio Engine
class AthanAudioManager: NSObject, ObservableObject {
    static let shared = AthanAudioManager()
    var audioPlayer: AVAudioPlayer?
    
    let fajrFileName = "Fajr_Athan.mp3"
    let regularFileName = "Main_Athan.mp3"
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    func playAthan(isFajr: Bool) {
        setupAudioSession()
        let targetName = isFajr ? fajrFileName : regularFileName
        
        guard let url = Bundle.main.url(forResource: targetName, withExtension: "m4a") else {
            print("Missing audio file: \(targetName).m4a")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            print("Playback error: \(error)")
        }
    }
    
    func stopAthan() {
        audioPlayer?.stop()
    }
}

// 2. Lock-Screen Automation Triggers for iOS Shortcuts
struct PlayFajrAthanIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Fajr Athan"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AthanAudioManager.shared.playAthan(isFajr: true)
        }
        return .result()
    }
}

struct PlayRegularAthanIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Regular Athan"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AthanAudioManager.shared.playAthan(isFajr: false)
        }
        return .result()
    }
}

// 3. Built-In Astronomical Prayer Times Calculator (ISNA + Last Third of Night)
struct OfflinePrayerCalculator {
    static func calculateTimes(date: Date, latitude: Double, longitude: Double) -> [(String, String, Date)] {
        let cal = Calendar.current
        
        func rawHoursForDay(_ targetDate: Date) -> (fajr: Double, dhuhr: Double, asr: Double, maghrib: Double, isha: Double) {
            let tzHours = Double(TimeZone.current.secondsFromGMT(for: targetDate)) / 3600.0
            let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: targetDate) ?? 1)
            let d = dayOfYear - 1.0
            let g = (2.0 * .pi / 365.0) * d
            
            let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
            
            let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
                                   - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
            
            let latRad = latitude * .pi / 180.0
            let solarNoonHours = 12.0 + tzHours - (longitude / 15.0) - (eqTime / 60.0)
            
            func hourAngle(angleDegrees: Double) -> Double {
                let angleRad = angleDegrees * .pi / 180.0
                let cosH = (sin(angleRad) - sin(latRad) * sin(decl)) / (cos(latRad) * cos(decl))
                let clamped = max(-1.0, min(1.0, cosH))
                return (acos(clamped) * 180.0 / .pi) / 15.0
            }
            
            let fajr = solarNoonHours - hourAngle(angleDegrees: -15.0)
            let dhuhr = solarNoonHours + (2.0 / 60.0)
            let asrAngle = atan(1.0 / (1.0 + tan(abs(latRad - decl)))) * 180.0 / .pi
            let asr = solarNoonHours + hourAngle(angleDegrees: asrAngle)
            let maghrib = solarNoonHours + hourAngle(angleDegrees: -0.833)
            let isha = solarNoonHours + hourAngle(angleDegrees: -15.0)
            
            return (fajr, dhuhr, asr, maghrib, isha)
        }
        
        let startOfToday = cal.startOfDay(for: date)
        let today = rawHoursForDay(date)
        
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: date) ?? date
        let startOfTomorrow = cal.startOfDay(for: tomorrowDate)
        let tomorrow = rawHoursForDay(tomorrowDate)
        
        let maghribDate = startOfToday.addingTimeInterval(today.maghrib * 3600.0)
        let nextFajrDate = startOfTomorrow.addingTimeInterval(tomorrow.fajr * 3600.0)
        
        // Night duration = from Maghrib to next Fajr; Last Third starts at Maghrib + (2/3 of night)
        let nightDuration = nextFajrDate.timeIntervalSince(maghribDate)
        let lastThirdDate = maghribDate.addingTimeInterval(nightDuration * (2.0 / 3.0))
        
        return [
            ("Fajr", "Fajr Athan", startOfToday.addingTimeInterval(today.fajr * 3600.0)),
            ("Dhuhr", "Main Athan", startOfToday.addingTimeInterval(today.dhuhr * 3600.0)),
            ("Asr", "Main Athan", startOfToday.addingTimeInterval(today.asr * 3600.0)),
            ("Maghrib", "Main Athan", maghribDate),
            ("Isha", "Main Athan", startOfToday.addingTimeInterval(today.isha * 3600.0)),
            ("Last Third of Night", "Tahajjud / Qiyam", lastThirdDate)
        ]
    }
}

// 4. Automatic GPS Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coords: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            coords = loc.coordinate
            manager.stopUpdatingLocation()
        }
    }
}

// 5. Main App Screen
struct ContentView: View {
    @StateObject private var audioManager = AthanAudioManager.shared
    @StateObject private var locationManager = LocationManager()
    @State private var prayerTimesList: [(String, String, Date)] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                List(prayerTimesList, id: \.0) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.0)
                                .font(.headline)
                            Text(item.1)
                                .font(.caption)
                                .foregroundColor(item.0 == "Last Third of Night" ? .indigo : .secondary)
                        }
                        Spacer()
                        Text(item.2, style: .time)
                            .font(.title3)
                            .foregroundColor(item.0 == "Last Third of Night" ? .indigo : .primary)
                    }
                }
                
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Test Fajr Athan") {
                            audioManager.playAthan(isFajr: true)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Test Main Athan") {
                            audioManager.playAthan(isFajr: false)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("Stop Audio") {
                        audioManager.stopAthan()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
            }
            .navigationTitle("My Athan")
            .onAppear {
                updatePrayers(lat: 37.7689, lon: -97.2695)
            }
            .onChange(of: locationManager.coords?.latitude) {
                if let c = locationManager.coords {
                    updatePrayers(lat: c.latitude, lon: c.longitude)
                }
            }
        }
    }
    
    func updatePrayers(lat: Double, lon: Double) {
        prayerTimesList = OfflinePrayerCalculator.calculateTimes(date: Date(), latitude: lat, longitude: lon)
    }
}
