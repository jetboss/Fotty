package com.pixelperfect.fotty.core.di

import com.pixelperfect.fotty.core.Config
import com.pixelperfect.fotty.core.network.api.football.FootballInterface
import com.pixelperfect.fotty.core.network.api.pocketbase.PocketBaseInterface
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.dnsoverhttps.DnsOverHttps
import java.net.InetAddress
import java.net.Inet4Address
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.HEADERS
        }
        
        // Create a bootstrap client to resolve the DoH endpoint
        val bootstrapClient = OkHttpClient.Builder()
            .addInterceptor(logging)
            .build()

        val cloudflareDns = DnsOverHttps.Builder()
            .client(bootstrapClient)
            .url("https://1.1.1.1/dns-query".toHttpUrl())
            .bootstrapDnsHosts(
                InetAddress.getByName("1.1.1.1"),
                InetAddress.getByName("1.0.0.1")
            )
            .build()

        val googleDns = DnsOverHttps.Builder()
            .client(bootstrapClient)
            .url("https://8.8.8.8/dns-query".toHttpUrl())
            .bootstrapDnsHosts(
                InetAddress.getByName("8.8.8.8"),
                InetAddress.getByName("8.8.4.4")
            )
            .build()

        val quad9Dns = DnsOverHttps.Builder()
            .client(bootstrapClient)
            .url("https://9.9.9.9/dns-query".toHttpUrl())
            .bootstrapDnsHosts(
                InetAddress.getByName("9.9.9.9"),
                InetAddress.getByName("149.112.112.112")
            )
            .build()

        return OkHttpClient.Builder()
            .dns(object : okhttp3.Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    val providers = listOf(cloudflareDns, googleDns, quad9Dns)
                    for (dns in providers) {
                        try {
                            val addresses = dns.lookup(hostname)
                            val ipv4Only = addresses.filter { it is Inet4Address }
                            val result = if (ipv4Only.isNotEmpty()) ipv4Only else addresses
                            android.util.Log.d("NetworkModule", "DoH Success ($hostname) via ${dns.url}")
                            return result
                        } catch (e: Exception) {
                            android.util.Log.w("NetworkModule", "DoH Failed ($hostname) via ${dns.url}: ${e.message}")
                        }
                    }
                    
                    // Final Fallback: System DNS
                    return try {
                        val systemResult = okhttp3.Dns.SYSTEM.lookup(hostname)
                        android.util.Log.d("NetworkModule", "System DNS Fallback Success: $hostname")
                        systemResult
                    } catch (e: Exception) {
                        android.util.Log.e("NetworkModule", "ALL DNS FAILED for $hostname")
                        throw e
                    }
                }
            })
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15")
                    .header("Referer", "https://p2p.pixel-invoice.com/")
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(logging)
            .build()
    }


    @Provides
    @Singleton
    fun provideFootballInterface(okHttpClient: OkHttpClient, json: Json): FootballInterface {
        return Retrofit.Builder()
            .baseUrl("https://api.football-data.org/v4/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(FootballInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideFottyFootballProxyInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface {
        val base = Config.footballProxyBaseURLString.trimEnd('/') + "/"
        return Retrofit.Builder()
            .baseUrl(base)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideAPIFootballInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.football.APIFootballInterface {
        return Retrofit.Builder()
            .baseUrl("https://v3.football.api-sports.io/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.football.APIFootballInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideFootballProInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.football.FootballProInterface {
        return Retrofit.Builder()
            .baseUrl("https://football-pro.p.rapidapi.com/v3/football/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.football.FootballProInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideHockeyInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.hockey.HockeyInterface {
        return Retrofit.Builder()
            .baseUrl("https://v1.hockey.api-sports.io/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.hockey.HockeyInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideCricketInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.cricket.CricketInterface {
        return Retrofit.Builder()
            .baseUrl("https://apiv2.api-cricket.com/cricket/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.cricket.CricketInterface::class.java)
    }


    @Provides
    @Singleton
    fun providePocketBaseInterface(okHttpClient: OkHttpClient, json: Json): PocketBaseInterface {
        return Retrofit.Builder()
            .baseUrl(Config.pocketBaseBaseURLString + "/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(PocketBaseInterface::class.java)
    }


    @Provides
    @Singleton
    fun provideSocialRepository(
        pbInterface: PocketBaseInterface,
        json: Json
    ): com.pixelperfect.fotty.core.network.repository.pocketbase.SocialRepository {
        return com.pixelperfect.fotty.core.network.repository.pocketbase.SocialRepository(pbInterface, json)
    }

    @Provides
    @Singleton
    fun provideFootballRepository(
        footballInterface: FootballInterface,
        fottyFootballProxy: com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface,
        apiFootballInterface: com.pixelperfect.fotty.core.network.api.football.APIFootballInterface,
        footballProInterface: com.pixelperfect.fotty.core.network.api.football.FootballProInterface
    ): com.pixelperfect.fotty.core.network.repository.football.FootballRepository {
        return com.pixelperfect.fotty.core.network.repository.football.FootballRepository(
            footballInterface,
            fottyFootballProxy,
            apiFootballInterface,
            footballProInterface
        )
    }

    @Provides
    @Singleton
    fun provideIFootballProvider(
        api: com.pixelperfect.fotty.core.network.api.football.APIFootballInterface
    ): com.pixelperfect.fotty.data.providers.IFootballProvider {
        return com.pixelperfect.fotty.data.providers.APIFootballProvider(api)
    }

    @Provides
    @Singleton
    fun provideNexusAlphaInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.nexus.NexusAlphaInterface {
        return Retrofit.Builder()
            .baseUrl("https://www.streamex.net/") // Default mirror, can be overridden by @Url
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.nexus.NexusAlphaInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideNexusAlphaProvider(
        api: com.pixelperfect.fotty.core.network.api.nexus.NexusAlphaInterface
    ): com.pixelperfect.fotty.data.providers.NexusAlphaProvider {
        return com.pixelperfect.fotty.data.providers.NexusAlphaProvider(api)
    }

    @Provides
    @Singleton
    fun provideP2PInterface(okHttpClient: OkHttpClient, json: Json): com.pixelperfect.fotty.core.network.api.p2p.P2PInterface {
        return Retrofit.Builder()
            .baseUrl("https://scraper.pixel-invoice.com/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(com.pixelperfect.fotty.core.network.api.p2p.P2PInterface::class.java)
    }

    @Provides
    @Singleton
    fun provideP2PProvider(
        api: com.pixelperfect.fotty.core.network.api.p2p.P2PInterface,
        okHttpClient: OkHttpClient
    ): com.pixelperfect.fotty.data.providers.P2PProvider {
        return com.pixelperfect.fotty.data.providers.P2PProvider(api, okHttpClient)
    }

    @Provides
    @Singleton
    fun provideMatchRepository(
        provider: com.pixelperfect.fotty.data.providers.IFootballProvider,
        footballDataApi: com.pixelperfect.fotty.core.network.api.football.FootballInterface,
        fottyFootballProxy: com.pixelperfect.fotty.core.network.api.football.FottyFootballProxyInterface,
        nexusProvider: com.pixelperfect.fotty.data.providers.NexusAlphaProvider,
        p2pService: com.pixelperfect.fotty.core.network.resolver.P2PDataService,
        hockeyApi: com.pixelperfect.fotty.core.network.api.hockey.HockeyInterface,
        cricketApi: com.pixelperfect.fotty.core.network.api.cricket.CricketInterface
    ): com.pixelperfect.fotty.data.repositories.MatchRepository {
        return com.pixelperfect.fotty.data.repositories.MatchRepository(
            provider, footballDataApi, fottyFootballProxy, nexusProvider, p2pService, hockeyApi, cricketApi
        )
    }

    @Provides
    @Singleton
    fun provideLeagueRepository(
        provider: com.pixelperfect.fotty.data.providers.IFootballProvider
    ): com.pixelperfect.fotty.data.repositories.LeagueRepository {
        return com.pixelperfect.fotty.data.repositories.LeagueRepository(provider)
    }

    @Provides
    @Singleton
    fun provideTeamRepository(
        provider: com.pixelperfect.fotty.data.providers.IFootballProvider
    ): com.pixelperfect.fotty.data.repositories.TeamRepository {
        return com.pixelperfect.fotty.data.repositories.TeamRepository(provider)
    }

    @Provides
    @Singleton
    fun provideP2PStreamEngine(
        p2pProvider: com.pixelperfect.fotty.data.providers.P2PProvider
    ): com.pixelperfect.fotty.core.network.engine.p2p.P2PStreamEngine {
        return p2pProvider
    }

    @Provides
    @Singleton
    fun provideStreamResolver(): com.pixelperfect.fotty.core.network.resolver.StreamResolver {
        return com.pixelperfect.fotty.core.network.resolver.StreamResolver()
    }

    @Provides
    @Singleton
    fun provideStreamRepository(
        nexusProvider: com.pixelperfect.fotty.data.providers.NexusAlphaProvider,
        p2pProvider: com.pixelperfect.fotty.data.providers.P2PProvider
    ): com.pixelperfect.fotty.data.repositories.StreamRepository {
        return com.pixelperfect.fotty.data.repositories.StreamRepository(nexusProvider, p2pProvider)
    }
}
